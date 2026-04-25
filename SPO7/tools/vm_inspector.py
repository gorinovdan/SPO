#!/usr/bin/env python3
import argparse
import base64
import contextlib
import json
import os
import struct
import tempfile
import io

import asm
import vm


def extract_metadata(meta_text):
    start = meta_text.find("{")
    end = meta_text.rfind("}")
    if start < 0 or end < start:
        return {}
    return json.loads(meta_text[start:end + 1])


def load_frame_mem(frame_info):
    return bytearray(base64.b64decode(frame_info["mem_b64"]))


def read_word(mem, addr):
    return struct.unpack_from("<i", mem, addr)[0]


def read_byte(mem, addr):
    return struct.unpack_from("<b", mem, addr)[0]


def read_slot(frame_info, addr, size):
    obj_mem = frame_info.get("obj_mem", {})
    key = str(addr)
    if key in obj_mem:
        return obj_mem[key]
    mem = load_frame_mem(frame_info)
    if size == 1:
        return {"kind": "int", "value": read_byte(mem, addr)}
    return {"kind": "int", "value": read_word(mem, addr)}


def build_data_labels(asm_path):
    has_sections, const_defs, data_defs, meta_defs, flat_defs, code_labels, code = asm.parse_asm(asm_path)
    if has_sections:
        _, data_labels, _ = asm.build_data_section(data_defs, asm_path)
        return data_labels
    _, data_labels, _ = asm.build_data_section(flat_defs, asm_path)
    return data_labels


def stringify_scalar(value):
    if value["kind"] == "address":
        return f"&{value['frame_id']}:{value['addr']}"
    if value["kind"] == "string":
        return repr(value["value"])
    return str(value["value"])


def resolve_runtime_type(types_by_id, header_value):
    if header_value["kind"] != "int":
        return None
    return types_by_id.get(header_value["value"])


def inspect_object(frames, types_by_name, types_by_id, value, static_type, visited):
    if value["kind"] != "address":
        return stringify_scalar(value)
    frame_id = value.get("frame_id")
    addr = value.get("addr")
    if frame_id is None or frame_id < 0 or frame_id >= len(frames):
        return "null"
    if (frame_id, addr) in visited:
        return "<cycle>"
    visited.add((frame_id, addr))
    frame = frames[frame_id]
    header = read_slot(frame, addr, 4)
    runtime_type = resolve_runtime_type(types_by_id, header) or types_by_name.get(static_type)
    if not runtime_type:
        visited.remove((frame_id, addr))
        return stringify_scalar(value)
    parts = []
    for field in runtime_type.get("fields", []):
        field_addr = addr + field["slot"] * 4
        field_value = read_slot(frame, field_addr, 4)
        field_type = field["type"]
        if field_type in types_by_name:
            field_repr = inspect_object(frames, types_by_name, types_by_id, field_value, field_type, visited)
        else:
            field_repr = stringify_scalar(field_value)
        parts.append(f"{field['name']}={field_repr}")
    visited.remove((frame_id, addr))
    return f"{runtime_type['name']}{{" + ", ".join(parts) + "}"


def run_and_capture(spec_path, bin_path):
    fd, state_path = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        spec, by_opcode = vm.load_spec(spec_path)
        binary = vm.parse_binary(bin_path, by_opcode)
        with contextlib.redirect_stdout(io.StringIO()):
            vm.run_vm(binary, spec, by_opcode, 1000000, state_path)
        with open(state_path, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(state_path):
            os.unlink(state_path)


def main():
    parser = argparse.ArgumentParser(description="Inspect SPO variables and user-type fields")
    parser.add_argument("-a", "--asm", required=True, help="Path to generated assembly")
    parser.add_argument("-b", "--bin", required=True, help="Path to assembled binary")
    parser.add_argument("-s", "--spec", required=True, help="Path to VM spec.json")
    parser.add_argument("--subprogram", default="main", help="Subprogram to inspect (default: main)")
    args = parser.parse_args()

    state = run_and_capture(args.spec, args.bin)
    metadata = extract_metadata(state.get("meta", ""))
    data_labels = build_data_labels(args.asm)
    frames = state.get("frames", [])
    if not frames:
        raise SystemExit("No VM frames captured")
    current_frame = frames[-1]

    types = metadata.get("types", [])
    types_by_name = {t["name"]: t for t in types}
    types_by_id = {t["typeId"]: t for t in types if t.get("typeId")}

    subprograms = {sp["name"]: sp for sp in metadata.get("subprograms", [])}
    subprogram = subprograms.get(args.subprogram)
    if not subprogram:
        raise SystemExit(f"Unknown subprogram in metadata: {args.subprogram}")

    for symbol in subprogram.get("symbols", []):
        label = symbol["label"]
        if label not in data_labels:
            continue
        addr = data_labels[label]
        raw_value = read_slot(current_frame, addr, 4)
        type_name = symbol.get("type", "")
        if type_name in types_by_name:
            rendered = inspect_object(frames, types_by_name, types_by_id, raw_value, type_name, set())
        else:
            rendered = stringify_scalar(raw_value)
        kind = "arg" if symbol.get("isParam") else "local"
        print(f"{kind} {symbol['name']}: {rendered}")


if __name__ == "__main__":
    main()
