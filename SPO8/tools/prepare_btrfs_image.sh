#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
IMAGE="$PROJECT_DIR/spo8_btrfs_block.img"
RESULTS_DIR="$PROJECT_DIR/results"
IMAGE_SIZE_MB="${SPO8_BTRFS_SIZE_MB:-160}"
LABEL="${SPO8_BTRFS_LABEL:-SPO8_REAL}"

mkdir -p "$RESULTS_DIR"

copy_excludes() {
    printf '%s\n' \
        --exclude '.git' \
        --exclude '.DS_Store' \
        --exclude 'app' \
        --exclude 'app.exe' \
        --exclude 'app.dSYM' \
        --exclude 'results' \
        --exclude 'spo8_btrfs_block.img'
}

prepare_with_linux_tools() {
    if ! command -v mkfs.btrfs >/dev/null 2>&1; then
        return 1
    fi
    if ! command -v btrfs >/dev/null 2>&1; then
        return 1
    fi
    if ! command -v mount >/dev/null 2>&1 || ! command -v umount >/dev/null 2>&1; then
        return 1
    fi
    if [ "$(uname -s)" != "Linux" ]; then
        return 1
    fi

    SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        if ! command -v sudo >/dev/null 2>&1; then
            return 1
        fi
        SUDO="sudo"
    fi

    MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spo8-btrfs.XXXXXX")
    mounted=0
    cleanup() {
        if [ "$mounted" -eq 1 ]; then
            $SUDO umount "$MOUNT_DIR" >/dev/null 2>&1 || true
        fi
        rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT INT TERM

    rm -f "$IMAGE"
    dd if=/dev/zero of="$IMAGE" bs=1M count="$IMAGE_SIZE_MB" status=none
    mkfs.btrfs -f -L "$LABEL" "$IMAGE" >/dev/null
    $SUDO mount -o loop "$IMAGE" "$MOUNT_DIR"
    mounted=1
    $SUDO mkdir -p "$MOUNT_DIR/SPO8"
    if command -v rsync >/dev/null 2>&1; then
        # shellcheck disable=SC2046
        $SUDO rsync -a --delete $(copy_excludes) "$PROJECT_DIR/" "$MOUNT_DIR/SPO8/"
    else
        (cd "$PROJECT_DIR" && tar --exclude='.git' --exclude='.DS_Store' \
            --exclude='app' --exclude='app.exe' --exclude='app.dSYM' \
            --exclude='results' --exclude='spo8_btrfs_block.img' -cf - .) |
            (cd "$MOUNT_DIR/SPO8" && $SUDO tar -xf -)
    fi
    sync
    $SUDO umount "$MOUNT_DIR"
    mounted=0

    btrfs inspect-internal dump-super -f "$IMAGE" > "$RESULTS_DIR/btrfs_real_super.txt"
    btrfs inspect-internal dump-tree -t chunk "$IMAGE" > "$RESULTS_DIR/btrfs_real_chunk.txt"
    btrfs inspect-internal dump-tree "$IMAGE" > "$RESULTS_DIR/btrfs_real_tree.txt"
    (cd "$PROJECT_DIR" && find . \
        -path './results' -prune -o \
        -path './spo8_btrfs_block.img' -prune -o \
        -path './app' -prune -o \
        -path './app.exe' -prune -o \
        -path './app.dSYM' -prune -o \
        -type f -print | sort) > "$RESULTS_DIR/btrfs_source_files.txt"
}

prepare_with_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Не найден mkfs.btrfs и не найден docker. Нужен btrfs-progs локально или Docker." >&2
        return 1
    fi

    DNS="${SPO8_DOCKER_DNS:-1.1.1.1}"
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)

    docker run --rm --privileged --dns "$DNS" \
        -e IMAGE_SIZE_MB="$IMAGE_SIZE_MB" \
        -e LABEL="$LABEL" \
        -e HOST_UID="$HOST_UID" \
        -e HOST_GID="$HOST_GID" \
        -v "$PROJECT_DIR:/work/project" \
        alpine:3.20 sh -euxc '
            apk add --no-cache btrfs-progs rsync coreutils >/dev/null
            cd /work/project
            mkdir -p results
            rm -f spo8_btrfs_block.img
            dd if=/dev/zero of=spo8_btrfs_block.img bs=1M count="$IMAGE_SIZE_MB" status=none
            mkfs.btrfs -f -L "$LABEL" spo8_btrfs_block.img >/dev/null
            mkdir -p /mnt/spo8
            mount -o loop spo8_btrfs_block.img /mnt/spo8
            mkdir -p /mnt/spo8/SPO8
            rsync -a --delete \
                --exclude ".git" \
                --exclude ".DS_Store" \
                --exclude "app" \
                --exclude "app.exe" \
                --exclude "app.dSYM" \
                --exclude "results" \
                --exclude "spo8_btrfs_block.img" \
                ./ /mnt/spo8/SPO8/
            sync
            umount /mnt/spo8
            btrfs inspect-internal dump-super -f spo8_btrfs_block.img > results/btrfs_real_super.txt
            btrfs inspect-internal dump-tree -t chunk spo8_btrfs_block.img > results/btrfs_real_chunk.txt
            btrfs inspect-internal dump-tree spo8_btrfs_block.img > results/btrfs_real_tree.txt
            find . \
                -path "./results" -prune -o \
                -path "./spo8_btrfs_block.img" -prune -o \
                -path "./app" -prune -o \
                -path "./app.exe" -prune -o \
                -path "./app.dSYM" -prune -o \
                -type f -print | sort > results/btrfs_source_files.txt
            chown "$HOST_UID:$HOST_GID" \
                spo8_btrfs_block.img \
                results/btrfs_real_super.txt \
                results/btrfs_real_chunk.txt \
                results/btrfs_real_tree.txt \
                results/btrfs_source_files.txt
        '
}

if [ "${SPO8_FORCE_DOCKER:-0}" != "1" ] && prepare_with_linux_tools; then
    :
else
    prepare_with_docker
fi

printf 'Btrfs-образ готов: %s\n' "$IMAGE"
printf 'Метаданные: %s\n' "$RESULTS_DIR/btrfs_real_tree.txt"
