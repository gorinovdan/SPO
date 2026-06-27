# Сдача SPO6-SPO8

Студент: Горинов Даниил Андреевич, группа P4116.

## Задания

| Задание | Папка в GitHub | Получить только эту папку | Отчёт |
| --- | --- | --- | --- |
| SPO6, практическое задание №1 | <https://github.com/gorinovdan/SPO/tree/main/SPO6> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO6 && cd SPO6 && git sparse-checkout set SPO6` | `SPO6/report-SPO6/report.pdf` |
| SPO7, практическое задание №2 | <https://github.com/gorinovdan/SPO/tree/main/SPO7> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO7 && cd SPO7 && git sparse-checkout set SPO7` | `SPO7/report-SPO7/report.pdf` |
| SPO8, практическое задание №3 | <https://github.com/gorinovdan/SPO/tree/main/SPO8> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO8 && cd SPO8 && git sparse-checkout set SPO8` | `SPO8/report-SPO8/report.pdf` |

## Проверка

```bash
make -C SPO6 remote-demo
make -C SPO7 remote-demo
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
make -C SPO8 remote-ftp-smoke
```
