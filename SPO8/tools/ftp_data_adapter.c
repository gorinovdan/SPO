#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

/*
 * Сетевой адаптер RemoteTasks <-> FileZilla.
 *
 * Внутри VM остаются FTP-сервер, разбор команд, текущий каталог,
 * разрешение путей, обход Btrfs и чтение BlockDevice. Адаптер делает только
 * транспортную работу:
 *   1) принимает несколько внешних control-соединений FileZilla и
 *      последовательно передаёт строки команд в один control-SimplePipe VM;
 *   2) прокидывает PASV data-сокет FileZilla к data-SimplePipe VM.
 *
 * Адаптер не читает Btrfs-образ, не знает файловых путей и не отправляет
 * служебные FTP-команды в VM. В текущей версии RemoteTasks reset-регистр
 * SimplePipe для tcp-потока зависает на переподключении, поэтому внешний
 * PASV-сокет закрывается здесь после короткой паузы в data-потоке VM.
 */

#define LINE_CAP 2048
#define RESPONSE_TIMEOUT_MS 300000
#define DATA_FIRST_TIMEOUT_MS 15000
#define DATA_NEXT_TIMEOUT_MS 5000

static volatile sig_atomic_t stop_requested = 0;

struct control_state {
    int vm_fd;
    pthread_mutex_t lock;
    char greeting[LINE_CAP];
    size_t greeting_len;
};

struct control_client_args {
    int client_fd;
    struct control_state *state;
};

struct data_args {
    int vm_fd;
    int ftp_listen_fd;
};

static void on_signal(int sig) {
    (void)sig;
    stop_requested = 1;
}

static int listen_on(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        exit(2);
    }

    int yes = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) < 0) {
        perror("setsockopt");
        close(fd);
        exit(2);
    }

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(fd);
        exit(2);
    }
    if (listen(fd, 16) < 0) {
        perror("listen");
        close(fd);
        exit(2);
    }
    return fd;
}

static int accept_retry(int listen_fd) {
    for (;;) {
        int fd = accept(listen_fd, NULL, NULL);
        if (fd >= 0) {
            return fd;
        }
        if (errno == EINTR && !stop_requested) {
            continue;
        }
        return -1;
    }
}

static int wait_readable(int fd, int timeout_ms) {
    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    for (;;) {
        int rc = select(fd + 1, &rfds, NULL, NULL, &tv);
        if (rc >= 0) {
            return rc;
        }
        if (errno == EINTR && !stop_requested) {
            continue;
        }
        return -1;
    }
}

static int write_all(int fd, const unsigned char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, buf + off, len - off);
        if (n > 0) {
            off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        return -1;
    }
    return 0;
}

static ssize_t read_line_plain(int fd, char *buf, size_t cap) {
    size_t off = 0;
    while (off + 1 < cap) {
        unsigned char ch;
        ssize_t n = read(fd, &ch, 1);
        if (n > 0) {
            buf[off++] = (char)ch;
            if (ch == '\n') {
                break;
            }
            continue;
        }
        if (n == 0) {
            break;
        }
        if (errno == EINTR) {
            continue;
        }
        return -1;
    }
    buf[off] = '\0';
    return off == 0 ? 0 : (ssize_t)off;
}

static ssize_t read_line_timeout(int fd, char *buf, size_t cap, int timeout_ms) {
    size_t off = 0;
    while (off + 1 < cap) {
        int ready = wait_readable(fd, timeout_ms);
        if (ready <= 0) {
            return ready == 0 && off > 0 ? (ssize_t)off : -1;
        }

        unsigned char ch;
        ssize_t n = read(fd, &ch, 1);
        if (n > 0) {
            buf[off++] = (char)ch;
            if (ch == '\n') {
                break;
            }
            continue;
        }
        if (n == 0) {
            break;
        }
        if (errno == EINTR) {
            continue;
        }
        return -1;
    }
    buf[off] = '\0';
    return off == 0 ? 0 : (ssize_t)off;
}

static int parse_status_line(const char *line, int *code, char *separator) {
    if (!isdigit((unsigned char)line[0]) ||
        !isdigit((unsigned char)line[1]) ||
        !isdigit((unsigned char)line[2])) {
        return 0;
    }
    *code = (line[0] - '0') * 100 + (line[1] - '0') * 10 + (line[2] - '0');
    *separator = line[3];
    return 1;
}

static int same_final_line(const char *line, int code) {
    return line[0] == (char)('0' + code / 100) &&
           line[1] == (char)('0' + (code / 10) % 10) &&
           line[2] == (char)('0' + code % 10) &&
           line[3] == ' ';
}

static int read_response(int vm_fd, int client_fd) {
    char line[LINE_CAP];
    int code = 0;
    char separator = 0;

    ssize_t n = read_line_timeout(vm_fd, line, sizeof(line), RESPONSE_TIMEOUT_MS);
    if (n <= 0) {
        return -1;
    }
    if (client_fd >= 0 && write_all(client_fd, (const unsigned char *)line, (size_t)n) < 0) {
        return -1;
    }

    if (!parse_status_line(line, &code, &separator)) {
        return 0;
    }

    if (separator == '-') {
        for (;;) {
            n = read_line_timeout(vm_fd, line, sizeof(line), RESPONSE_TIMEOUT_MS);
            if (n <= 0) {
                return -1;
            }
            if (client_fd >= 0 && write_all(client_fd, (const unsigned char *)line, (size_t)n) < 0) {
                return -1;
            }
            if (same_final_line(line, code)) {
                break;
            }
        }
    }

    return code;
}

static int read_full_response(int vm_fd, int client_fd) {
    int code = read_response(vm_fd, client_fd);
    if (code >= 100 && code < 200) {
        int final_code = read_response(vm_fd, client_fd);
        if (final_code < 0) {
            return -1;
        }
    }
    return code;
}

static void normalize_client_line(char *line, ssize_t *len) {
    while (*len > 0 && (line[*len - 1] == '\n' || line[*len - 1] == '\r')) {
        (*len)--;
    }
    line[(*len)++] = '\r';
    line[(*len)++] = '\n';
    line[*len] = '\0';
}

static int is_quit_command(const char *line) {
    return (line[0] == 'q' || line[0] == 'Q') &&
           (line[1] == 'u' || line[1] == 'U') &&
           (line[2] == 'i' || line[2] == 'I') &&
           (line[3] == 't' || line[3] == 'T') &&
           (line[4] == '\r' || line[4] == '\n' || line[4] == ' ' || line[4] == '\0');
}

static void *control_client_thread(void *opaque) {
    struct control_client_args *args = (struct control_client_args *)opaque;
    int client_fd = args->client_fd;
    struct control_state *state = args->state;
    free(args);

    if (state->greeting_len > 0) {
        if (write_all(client_fd, (const unsigned char *)state->greeting, state->greeting_len) < 0) {
            close(client_fd);
            return NULL;
        }
    }

    for (;;) {
        char line[LINE_CAP];
        ssize_t len = read_line_plain(client_fd, line, sizeof(line) - 3);
        if (len <= 0) {
            break;
        }
        normalize_client_line(line, &len);

        if (is_quit_command(line)) {
            static const char reply[] = "221 bye\r\n";
            (void)write_all(client_fd, (const unsigned char *)reply, sizeof(reply) - 1);
            break;
        }

        pthread_mutex_lock(&state->lock);
        int ok = write_all(state->vm_fd, (const unsigned char *)line, (size_t)len);
        if (ok == 0) {
            ok = read_full_response(state->vm_fd, client_fd) < 0 ? -1 : 0;
        }
        pthread_mutex_unlock(&state->lock);

        if (ok < 0) {
            break;
        }
    }

    close(client_fd);
    return NULL;
}

static void *data_thread(void *opaque) {
    struct data_args *args = (struct data_args *)opaque;
    int vm_fd = args->vm_fd;
    int ftp_listen_fd = args->ftp_listen_fd;
    free(args);

    while (!stop_requested) {
        int ftp_fd = accept_retry(ftp_listen_fd);
        if (ftp_fd < 0) {
            break;
        }

        unsigned char buf[8192];
        int got_any = 0;
        for (;;) {
            int timeout = got_any ? DATA_NEXT_TIMEOUT_MS : DATA_FIRST_TIMEOUT_MS;
            int ready = wait_readable(vm_fd, timeout);
            if (ready == 0) {
                break;
            }
            if (ready < 0) {
                stop_requested = 1;
                break;
            }

            ssize_t n = read(vm_fd, buf, sizeof(buf));
            if (n == 0) {
                stop_requested = 1;
                break;
            }
            if (n < 0) {
                if (errno == EINTR) {
                    continue;
                }
                stop_requested = 1;
                break;
            }
            got_any = 1;
            if (write_all(ftp_fd, buf, (size_t)n) < 0) {
                break;
            }
        }

        shutdown(ftp_fd, SHUT_WR);
        close(ftp_fd);
    }

    close(vm_fd);
    return NULL;
}

int main(int argc, char **argv) {
    int ftp_control_port = 2121;
    int vm_control_port = 3121;
    int ftp_data_port = 2020;
    int vm_data_port = 3020;
    if (argc > 1) {
        ftp_control_port = atoi(argv[1]);
    }
    if (argc > 2) {
        vm_control_port = atoi(argv[2]);
    }
    if (argc > 3) {
        ftp_data_port = atoi(argv[3]);
    }
    if (argc > 4) {
        vm_data_port = atoi(argv[4]);
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    int ftp_control_listen = listen_on(ftp_control_port);
    int vm_control_listen = listen_on(vm_control_port);
    int ftp_data_listen = listen_on(ftp_data_port);
    int vm_data_listen = listen_on(vm_data_port);

    fprintf(stderr,
            "SPO8 адаптер FTP: control 127.0.0.1:%d -> VM 127.0.0.1:%d, "
            "data 127.0.0.1:%d -> VM 127.0.0.1:%d\n",
            ftp_control_port, vm_control_port, ftp_data_port, vm_data_port);
    fflush(stderr);

    int vm_control_fd = accept_retry(vm_control_listen);
    if (vm_control_fd < 0) {
        return 1;
    }
    fprintf(stderr, "SPO8 адаптер FTP: управляющий поток VM подключён\n");
    fflush(stderr);

    struct control_state state;
    memset(&state, 0, sizeof(state));
    state.vm_fd = vm_control_fd;
    pthread_mutex_init(&state.lock, NULL);

    ssize_t greeting_len = read_line_timeout(vm_control_fd, state.greeting,
                                             sizeof(state.greeting),
                                             RESPONSE_TIMEOUT_MS);
    if (greeting_len <= 0) {
        fprintf(stderr, "SPO8 адаптер FTP: VM не прислала FTP-приветствие\n");
        close(vm_control_fd);
        return 1;
    }
    state.greeting_len = (size_t)greeting_len;

    int vm_data_fd = accept_retry(vm_data_listen);
    if (vm_data_fd < 0) {
        close(vm_control_fd);
        return 1;
    }
    fprintf(stderr, "SPO8 адаптер FTP: поток данных VM подключён\n");
    fflush(stderr);

    struct data_args *dargs = (struct data_args *)calloc(1, sizeof(*dargs));
    if (dargs == NULL) {
        perror("calloc");
        close(vm_control_fd);
        close(vm_data_fd);
        return 2;
    }
    dargs->vm_fd = vm_data_fd;
    dargs->ftp_listen_fd = ftp_data_listen;

    pthread_t data_tid;
    if (pthread_create(&data_tid, NULL, data_thread, dargs) != 0) {
        perror("pthread_create");
        free(dargs);
        close(vm_control_fd);
        close(vm_data_fd);
        return 2;
    }
    pthread_detach(data_tid);

    while (!stop_requested) {
        int client_fd = accept_retry(ftp_control_listen);
        if (client_fd < 0) {
            break;
        }

        struct control_client_args *cargs =
            (struct control_client_args *)calloc(1, sizeof(*cargs));
        if (cargs == NULL) {
            close(client_fd);
            continue;
        }
        cargs->client_fd = client_fd;
        cargs->state = &state;

        pthread_t tid;
        if (pthread_create(&tid, NULL, control_client_thread, cargs) != 0) {
            close(client_fd);
            free(cargs);
            continue;
        }
        pthread_detach(tid);
    }

    close(vm_control_fd);
    close(ftp_control_listen);
    close(vm_control_listen);
    close(ftp_data_listen);
    close(vm_data_listen);
    return 0;
}
