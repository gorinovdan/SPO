# SPO — лабораторные работы

Студент: Горинов Даниил Андреевич
Группа: P4116
Дисциплины: «Системное программное обеспечение», «Системное программное обеспечение 2»

## Навигация

| Задание | Папка | Отчёт |
| --- | --- | --- |
| Практическое задание №1, СПО | [SPO1](SPO1/) | [PDF](SPO1/report-SPO1/report.pdf) |
| Практическое задание №2, СПО | [SPO2](SPO2/) | [PDF](SPO2/report-SPO2/report.pdf) |
| Практическое задание №3, СПО | [SPO3](SPO3/) | [PDF](SPO3/report-SPO3/report.pdf) |
| Практическое задание №5, СПО | [SPO5](SPO5/) | [README](SPO5/README.md) |
| Практическое задание №1, СПО 2 | [SPO6](SPO6/) | [PDF](SPO6/report-SPO6/report.pdf) |
| Практическое задание №2, СПО 2 | [SPO7](SPO7/) | [PDF](SPO7/report-SPO7/report.pdf) |
| Практическое задание №3, СПО 2 | [SPO8](SPO8/) | [PDF](SPO8/report-SPO8/report.pdf) |

## Ссылки на папки текущего семестра

| Задание | Папка в GitHub | Получить только эту папку |
| --- | --- | --- |
| SPO6 | <https://github.com/gorinovdan/SPO/tree/main/SPO6> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO6 && cd SPO6 && git sparse-checkout set SPO6` |
| SPO7 | <https://github.com/gorinovdan/SPO/tree/main/SPO7> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO7 && cd SPO7 && git sparse-checkout set SPO7` |
| SPO8 | <https://github.com/gorinovdan/SPO/tree/main/SPO8> | `git clone --filter=blob:none --sparse https://github.com/gorinovdan/SPO.git SPO8 && cd SPO8 && git sparse-checkout set SPO8` |

## Проверка текущего семестра

```bash
make -C SPO6 remote-demo
make -C SPO7 remote-demo
make -C SPO8 remote-demo
make -C SPO8 remote-unsupported
make -C SPO8 remote-ftp-smoke
```
