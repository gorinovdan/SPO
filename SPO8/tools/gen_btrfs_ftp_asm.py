#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


BEGIN = "; BEGIN GENERATED BTRFS TABLES"
END = "; END GENERATED BTRFS TABLES"


@dataclass
class Chunk:
    logical: int
    length: int
    physical: int


@dataclass
class CurrentItem:
    objid: int
    kind: str
    itemoff: int
    itemsize: int
    leaf_physical: int


def parse_chunks(path: Path) -> list[Chunk]:
    chunks: list[Chunk] = []
    current_logical: int | None = None
    current_length: int | None = None
    current_physical: int | None = None

    def flush() -> None:
        nonlocal current_logical, current_length, current_physical
        if current_logical is not None and current_length is not None and current_physical is not None:
            chunks.append(Chunk(current_logical, current_length, current_physical))
        current_logical = None
        current_length = None
        current_physical = None

    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.search(r"key \(FIRST_CHUNK_TREE CHUNK_ITEM (\d+)\)", line)
        if match:
            flush()
            current_logical = int(match.group(1))
            continue
        if current_logical is None:
            continue
        match = re.search(r"\blength (\d+)\b", line)
        if match and current_length is None:
            current_length = int(match.group(1))
            continue
        match = re.search(r"stripe 0 devid \d+ offset (\d+)", line)
        if match and current_physical is None:
            current_physical = int(match.group(1))
            continue

    flush()
    if not chunks:
        raise ValueError(f"не удалось разобрать chunk tree: {path}")
    return chunks


def logical_to_physical(chunks: list[Chunk], logical: int) -> int:
    for chunk in chunks:
        if chunk.logical <= logical < chunk.logical + chunk.length:
            return chunk.physical + (logical - chunk.logical)
    raise ValueError(f"нет chunk item для logical={logical}")


def btrfs_type(raw_type: str, mode: int | None = None) -> int:
    if raw_type == "DIR":
        return 2
    if raw_type == "FILE":
        return 1
    if mode is not None:
        mode_text = str(mode)
        if mode_text.startswith("40"):
            return 2
        if mode_text.startswith("100"):
            return 1
    return 0


def parse_tree(path: Path, chunks: list[Chunk]) -> tuple[int, dict[int, dict[str, int]], list[dict[str, int | str]], dict[int, dict[str, int]]]:
    root_inode = 256
    inodes: dict[int, dict[str, int]] = {}
    dirents: list[dict[str, int | str]] = []
    extents: dict[int, dict[str, int]] = {}

    current: CurrentItem | None = None
    current_leaf_physical = 0
    in_fs_leaf = False

    def finish_item() -> None:
        pass

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip("\n")

        match = re.search(r"\broot_dirid (\d+) bytenr .*\blevel \d+", line)
        if match and "generation" in line:
            root_inode = int(match.group(1))

        match = re.match(r"leaf (\d+) items .* owner (\S+)", line)
        if match:
            finish_item()
            in_fs_leaf = match.group(2) == "FS_TREE"
            current_leaf_physical = logical_to_physical(chunks, int(match.group(1))) if in_fs_leaf else 0
            current = None
            continue

        if not in_fs_leaf:
            continue

        match = re.match(r"\s*item \d+ key \((\d+) ([A-Z_]+) \d+\) itemoff (\d+) itemsize (\d+)", line)
        if match:
            finish_item()
            current = CurrentItem(
                objid=int(match.group(1)),
                kind=match.group(2),
                itemoff=int(match.group(3)),
                itemsize=int(match.group(4)),
                leaf_physical=current_leaf_physical,
            )
            continue

        if current is None:
            continue

        if current.kind == "INODE_ITEM":
            match = re.search(r"\bsize (\d+)\b", line)
            if match:
                inodes.setdefault(current.objid, {})["size"] = int(match.group(1))
            match = re.search(r"\bmode (\d+)\b", line)
            if match:
                inodes.setdefault(current.objid, {})["type"] = btrfs_type("", int(match.group(1)))
            continue

        if current.kind == "DIR_ITEM":
            match = re.search(r"location key \((\d+) INODE_ITEM 0\) type (\S+)", line)
            if match:
                current_dirent = {
                    "parent": current.objid,
                    "inode": int(match.group(1)),
                    "type": btrfs_type(match.group(2)),
                    "name": "",
                }
                dirents.append(current_dirent)
                continue
            match = re.search(r"name: (.*)$", line)
            if match and dirents:
                dirents[-1]["name"] = match.group(1)
            continue

        if current.kind == "EXTENT_DATA":
            match = re.search(r"generation \d+ type 0 \(inline\)", line)
            if match:
                continue
            match = re.search(r"inline extent data size (\d+)", line)
            if match:
                size = int(match.group(1))
                # itemoff в dump-tree дан относительно области данных leaf.
                # Перед ней находится 101-байтовый btrfs_header, а внутри
                # btrfs_file_extent_item встроенные данные начинаются после
                # 21-байтового заголовка.
                extents[current.objid] = {
                    "block_off": current.leaf_physical + 101 + current.itemoff + 21,
                    "size": size,
                }
                continue
            match = re.search(r"extent data disk byte (\d+) nr (\d+)", line)
            if match:
                disk_byte = int(match.group(1))
                disk_len = int(match.group(2))
                extents.setdefault(current.objid, {})["disk_byte"] = disk_byte
                extents.setdefault(current.objid, {})["disk_len"] = disk_len
                continue
            match = re.search(r"extent data offset (\d+) nr (\d+) ram", line)
            if match:
                data_offset = int(match.group(1))
                data_len = int(match.group(2))
                item = extents.setdefault(current.objid, {})
                disk_byte = item.get("disk_byte")
                if disk_byte is None:
                    continue
                item["block_off"] = logical_to_physical(chunks, int(disk_byte) + data_offset)
                item["size"] = data_len
                continue

    clean_dirents = [d for d in dirents if d["name"]]
    for dirent in clean_dirents:
        inode = int(dirent["inode"])
        inodes.setdefault(inode, {}).setdefault("type", int(dirent["type"]))
        inodes.setdefault(inode, {}).setdefault("size", 0)

    for inode, meta in list(inodes.items()):
        meta.setdefault("size", 0)
        meta.setdefault("type", 0)
        if meta["type"] == 0:
            del inodes[inode]

    return root_inode, inodes, clean_dirents, {
        inode: meta for inode, meta in extents.items() if "block_off" in meta and "size" in meta
    }


def quote_bytes(text: str) -> str:
    data = text.encode("utf-8")
    parts: list[str] = []
    for byte in data:
        if byte == 0x22:
            parts.append('\\"')
        elif byte == 0x5C:
            parts.append("\\\\")
        elif 32 <= byte <= 126:
            parts.append(chr(byte))
        else:
            raise ValueError(f"имя содержит не ASCII-байт 0x{byte:02x}: {text!r}")
    return '"' + "".join(parts) + '"'


def dd_array(label: str, values: list[int]) -> list[str]:
    if not values:
        return [f"{label}: DD 0"]
    lines = [f"{label}: DD {values[0]}"]
    for idx, value in enumerate(values[1:], 1):
        lines.append(f"{label}_{idx}: DD {value}")
    return lines


def generate_tables(root_inode: int, inodes: dict[int, dict[str, int]], dirents: list[dict[str, int | str]], extents: dict[int, dict[str, int]]) -> str:
    name_ids: dict[str, int] = {}
    name_pool = bytearray()
    name_offsets: list[int] = []
    name_lengths: list[int] = []

    for dirent in dirents:
        name = str(dirent["name"])
        if name in name_ids:
            continue
        name_ids[name] = len(name_ids)
        raw = name.encode("utf-8")
        name_offsets.append(len(name_pool))
        name_lengths.append(len(raw))
        name_pool.extend(raw)

    sorted_inodes = sorted(inodes)
    sorted_extents = sorted(extents)

    lines: list[str] = [
        BEGIN,
        ";",
        "; Этот раздел генерируется из настоящего Btrfs-образа,",
        "; созданного через mkfs.btrfs, mount, копирование SPO8 и umount.",
        "; В VM таблицы используются как индекс дерева, а байты RETR/COPY",
        "; читаются напрямую из BlockDevice по физическим смещениям extent.",
        "; ---------------------------------------------------------------------",
        f"img_root_inode: DD {root_inode}",
        "",
        f"img_inode_count: DD {len(sorted_inodes)}",
    ]
    lines.extend(dd_array("img_inode_objectid", sorted_inodes))
    lines.extend(dd_array("img_inode_type", [inodes[i]["type"] for i in sorted_inodes]))
    lines.extend(dd_array("img_inode_size", [inodes[i]["size"] for i in sorted_inodes]))

    lines.extend([
        "",
        f"img_dirent_count: DD {len(dirents)}",
    ])
    lines.extend(dd_array("img_dirent_parent", [int(d["parent"]) for d in dirents]))
    lines.extend(dd_array("img_dirent_inode", [int(d["inode"]) for d in dirents]))
    lines.extend(dd_array("img_dirent_type", [int(d["type"]) for d in dirents]))
    lines.extend(dd_array("img_dirent_name_id", [name_ids[str(d["name"])] for d in dirents]))

    lines.extend([
        "",
        f"img_extent_count: DD {len(sorted_extents)}",
    ])
    lines.extend(dd_array("img_extent_inode", sorted_extents))
    lines.extend(dd_array("img_extent_block_off", [extents[i]["block_off"] for i in sorted_extents]))
    lines.extend(dd_array("img_extent_size", [extents[i]["size"] for i in sorted_extents]))

    lines.extend([
        "",
        f"img_name_count: DD {len(name_ids)}",
    ])
    lines.extend(dd_array("img_name_offset", name_offsets))
    lines.extend(dd_array("img_name_len", name_lengths))
    lines.append(f"img_name_pool: DB {quote_bytes(name_pool.decode('utf-8'))}")
    lines.append(END)
    return "\n".join(lines) + "\n"


def replace_generated_section(template: str, generated: str) -> str:
    start = template.index(BEGIN)
    stop = template.index(END, start) + len(END)
    return template[:start] + generated.rstrip("\n") + template[stop:]


def main() -> int:
    parser = argparse.ArgumentParser(description="Сгенерировать таблицы FTP-Btrfs для SPO8")
    parser.add_argument("--template", required=True)
    parser.add_argument("--chunk", required=True)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    chunks = parse_chunks(Path(args.chunk))
    root_inode, inodes, dirents, extents = parse_tree(Path(args.tree), chunks)
    generated = generate_tables(root_inode, inodes, dirents, extents)
    template = Path(args.template).read_text(encoding="utf-8")
    output = replace_generated_section(template, generated)
    Path(args.output).write_text(output, encoding="utf-8")

    print(f"Сгенерировано: inode={len(inodes)} dirent={len(dirents)} extent={len(extents)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
