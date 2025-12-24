#!/usr/bin/env python3
import argparse
import json
import struct
import sys

CONST_KIND_INT = 0
CONST_KIND_BOOL = 1
CONST_KIND_CHAR = 2
CONST_KIND_STRING = 3


def load_spec(path):
    with open(path, "r", encoding="utf-8") as f:
        spec = json.load(f)
    by_mnemonic = {}
    by_opcode = {}
    for ins in spec.get("instructions", []):
        by_mnemonic[ins["mnemonic"].upper()] = ins
        by_opcode[ins["opcode"]] = ins
    return spec, by_mnemonic, by_opcode


def strip_comment(line):
    for token in (";", "//"):
        idx = line.find(token)
        if idx >= 0:
            line = line[:idx]
    return line.strip()


def unescape_string(s):
    if len(s) < 2 or s[0] != '"' or s[-1] != '"':
        raise ValueError("invalid string literal")
    body = s[1:-1]
    return bytes(body, "utf-8").decode("unicode_escape")


def parse_char_literal(s):
    s = s.strip()
    if len(s) < 2 or s[0] != "'" or s[-1] != "'":
        raise ValueError("invalid char literal")
    body = s[1:-1]
    if body.startswith("\\"):
        esc = body[1:]
        if esc == "n":
            return ord("\n")
        if esc == "t":
            return ord("\t")
        if esc == "\\":
            return ord("\\")
        if esc == "'":
            return ord("'")
        if esc == '"':
            return ord('"')
        raise ValueError("unsupported char escape")
    if len(body) != 1:
        raise ValueError("invalid char literal")
    return ord(body)


def int_to_bytes(value, size):
    if size == 1:
        return struct.pack("<b", int(value))
    if size == 4:
        return struct.pack("<i", int(value))
    raise ValueError("unsupported size")


def parse_asm(path):
    section = None
    consts = []
    const_labels = {}
    data_labels = {}
    data_items = []
    data_bytes = bytearray()
    code_labels = {}
    code = []

    with open(path, "r", encoding="utf-8") as f:
        for line_no, raw in enumerate(f, 1):
            line = strip_comment(raw)
            if not line:
                continue
            if line.startswith(".const"):
                section = "const"
                continue
            if line.startswith(".data"):
                section = "data"
                continue
            if line.startswith(".code"):
                section = "code"
                continue

            if section in ("const", "data"):
                if ":" not in line:
                    raise ValueError(f"{path}:{line_no}: missing label")
                label, rest = line.split(":", 1)
                label = label.strip()
                rest = rest.strip()
                if not rest.startswith("."):
                    raise ValueError(f"{path}:{line_no}: missing directive")
                parts = rest.split(None, 1)
                directive = parts[0]
                arg = parts[1].strip() if len(parts) > 1 else ""

                if section == "const":
                    if label in const_labels:
                        raise ValueError(f"{path}:{line_no}: duplicate const label {label}")
                    if directive == ".string":
                        value = unescape_string(arg)
                        const_labels[label] = len(consts)
                        consts.append({"kind": CONST_KIND_STRING, "value": value})
                    elif directive == ".char":
                        value = parse_char_literal(arg)
                        const_labels[label] = len(consts)
                        consts.append({"kind": CONST_KIND_CHAR, "value": value})
                    elif directive in (".int", ".word", ".byte"):
                        value = int(arg, 0) if arg else 0
                        const_labels[label] = len(consts)
                        consts.append({"kind": CONST_KIND_INT, "value": value, "size": 4 if directive != ".byte" else 1})
                    else:
                        raise ValueError(f"{path}:{line_no}: unsupported const directive {directive}")
                else:
                    if label in data_labels:
                        raise ValueError(f"{path}:{line_no}: duplicate data label {label}")
                    if directive in (".int", ".word"):
                        value = int(arg, 0) if arg else 0
                        addr = len(data_bytes)
                        data_bytes.extend(int_to_bytes(value, 4))
                        data_labels[label] = addr
                        data_items.append({"name": label, "addr": addr, "size": 4})
                    elif directive == ".byte":
                        value = int(arg, 0) if arg else 0
                        addr = len(data_bytes)
                        data_bytes.extend(int_to_bytes(value, 1))
                        data_labels[label] = addr
                        data_items.append({"name": label, "addr": addr, "size": 1})
                    elif directive == ".char":
                        value = parse_char_literal(arg)
                        addr = len(data_bytes)
                        data_bytes.extend(int_to_bytes(value, 1))
                        data_labels[label] = addr
                        data_items.append({"name": label, "addr": addr, "size": 1})
                    elif directive == ".space":
                        size = int(arg, 0) if arg else 0
                        if size < 0:
                            raise ValueError(f"{path}:{line_no}: invalid .space size")
                        addr = len(data_bytes)
                        data_bytes.extend(b"\x00" * size)
                        data_labels[label] = addr
                        data_items.append({"name": label, "addr": addr, "size": size})
                    else:
                        raise ValueError(f"{path}:{line_no}: unsupported data directive {directive}")
                continue

            if section == "code":
                if line.endswith(":"):
                    label = line[:-1].strip()
                    if label in code_labels:
                        raise ValueError(f"{path}:{line_no}: duplicate code label {label}")
                    code_labels[label] = len(code)
                    continue
                parts = line.split(None, 1)
                mnemonic = parts[0].upper()
                operands = []
                if len(parts) > 1:
                    operands = [op.strip() for op in parts[1].split(",") if op.strip()]
                code.append({"mnemonic": mnemonic, "operands": operands, "line": line_no})
                continue

            raise ValueError(f"{path}:{line_no}: content outside sections")

    return consts, const_labels, data_items, data_labels, data_bytes, code_labels, code


def assemble(spec_path, asm_path, out_path):
    _, by_mnemonic, _ = load_spec(spec_path)
    consts, const_labels, data_items, data_labels, data_bytes, code_labels, code = parse_asm(asm_path)

    imports = []
    import_index = {}
    encoded_code = []

    for inst in code:
        if inst["mnemonic"] not in by_mnemonic:
            raise ValueError(f"{asm_path}:{inst['line']}: unknown instruction {inst['mnemonic']}")
        spec = by_mnemonic[inst["mnemonic"]]
        opspec = spec.get("operands", [])
        if len(inst["operands"]) != len(opspec):
            raise ValueError(f"{asm_path}:{inst['line']}: operand count mismatch for {inst['mnemonic']}")

        encoded_ops = []
        for op_text, op_type in zip(inst["operands"], opspec):
            if op_type == "imm":
                encoded_ops.append(int(op_text, 0))
            elif op_type == "const":
                if op_text not in const_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown const {op_text}")
                encoded_ops.append(const_labels[op_text])
            elif op_type == "data":
                if op_text not in data_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown data {op_text}")
                encoded_ops.append(data_labels[op_text])
            elif op_type == "code":
                if op_text not in code_labels:
                    raise ValueError(f"{asm_path}:{inst['line']}: unknown label {op_text}")
                encoded_ops.append(code_labels[op_text])
            elif op_type == "code_or_builtin":
                if op_text in code_labels:
                    encoded_ops.append(code_labels[op_text])
                else:
                    if op_text not in import_index:
                        import_index[op_text] = len(imports)
                        imports.append(op_text)
                    encoded_ops.append(-(import_index[op_text] + 1))
            else:
                raise ValueError(f"{asm_path}:{inst['line']}: unsupported operand type {op_type}")

        encoded_code.append({"opcode": spec["opcode"], "operands": encoded_ops})

    entry_ip = code_labels.get("main", 0)

    with open(out_path, "wb") as f:
        f.write(b"SPO3")
        f.write(struct.pack("<B", 1))
        f.write(struct.pack("<B", 4))
        f.write(struct.pack("<H", 0))
        f.write(struct.pack("<I", len(consts)))
        f.write(struct.pack("<I", len(data_bytes)))
        f.write(struct.pack("<I", len(encoded_code)))
        f.write(struct.pack("<I", entry_ip))
        f.write(struct.pack("<I", len(imports)))
        f.write(struct.pack("<I", len(data_items)))

        for c in consts:
            kind = c.get("kind", CONST_KIND_INT)
            if kind == CONST_KIND_STRING:
                encoded = c["value"].encode("utf-8")
                f.write(struct.pack("<B", kind))
                f.write(struct.pack("<I", len(encoded)))
                f.write(encoded)
            elif kind == CONST_KIND_CHAR:
                f.write(struct.pack("<B", kind))
                f.write(struct.pack("<I", 1))
                f.write(int_to_bytes(c["value"], 1))
            elif kind in (CONST_KIND_INT, CONST_KIND_BOOL):
                size = c.get("size", 4)
                f.write(struct.pack("<B", CONST_KIND_INT))
                f.write(struct.pack("<I", size))
                f.write(int_to_bytes(c["value"], size))
            else:
                raise ValueError("unsupported const kind")

        for item in data_items:
            f.write(struct.pack("<I", item["addr"]))
            f.write(struct.pack("<I", item["size"]))

        f.write(data_bytes)

        for name in imports:
            enc = name.encode("utf-8")
            f.write(struct.pack("<I", len(enc)))
            f.write(enc)

        for inst in encoded_code:
            f.write(struct.pack("<B", inst["opcode"]))
            for op in inst["operands"]:
                f.write(struct.pack("<i", int(op)))


def main():
    parser = argparse.ArgumentParser(description="Assemble SPO3 VM listing")
    parser.add_argument("-s", "--spec", required=True, help="Path to VM spec.json")
    parser.add_argument("-i", "--input", required=True, help="Input .asm file")
    parser.add_argument("-o", "--output", required=True, help="Output .bin file")
    args = parser.parse_args()

    try:
        assemble(args.spec, args.input, args.output)
    except Exception as exc:
        print(f"asm error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
