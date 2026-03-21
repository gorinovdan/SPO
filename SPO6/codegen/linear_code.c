#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>

#include "linear_code.h"

#define VM_WORD_SIZE 4
#define DEFAULT_INDEX_ELEMS 64

typedef struct VarEntry {
	char* name;
	char* label;
	char* type;
	int size;
	int is_ref;
	int is_auto_object;
	char* object_label;
	int object_size;
	int type_id;
} VarEntry;

typedef struct VarTable {
	VarEntry* entries;
	int count;
	int capacity;
} VarTable;

typedef struct EmitCtx {
	LC_Program* program;
	VarTable* vars;
	LC_CodeBlock* block;
	const CFG_Subprogram* subprogram;
	const CFG_Analysis* analysis;
} EmitCtx;

typedef struct IntVec {
	int* data;
	int count;
	int capacity;
} IntVec;

static char* xstrdup(const char* s) {
	if (!s) return NULL;
	size_t len = strlen(s) + 1;
	char* p = malloc(len);
	if (!p) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	memcpy(p, s, len);
	return p;
}

static const CFG_UserType* find_type(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return NULL;
	for (int i = 0; i < analysis->type_count; i++) {
		if (analysis->types[i].name && strcmp(analysis->types[i].name, name) == 0) return &analysis->types[i];
	}
	return NULL;
}

static const CFG_Subprogram* find_subprogram(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return NULL;
	for (int i = 0; i < analysis->subprogram_count; i++) {
		if (analysis->subprograms[i].name && strcmp(analysis->subprograms[i].name, name) == 0) return &analysis->subprograms[i];
	}
	return NULL;
}

static int type_is_array(const char* type_str) {
	return type_str && strstr(type_str, "array[") != NULL;
}

static int type_is_object_like(const CFG_Analysis* analysis, const char* type_str) {
	return find_type(analysis, type_str) != NULL;
}

static int parse_array_dim(const char* type_str) {
	if (!type_str) return 0;
	const char* start = strstr(type_str, "array[");
	if (!start) return 0;
	start += 6;
	char* end = NULL;
	long dim = strtol(start, &end, 0);
	if (!end || *end != ']') return 0;
	return dim > 0 ? (int)dim : 0;
}

static int size_for_type_name(const CFG_Analysis* analysis, const char* type_name) {
	if (!type_name || type_name[0] == '\0') return 4;
	if (type_is_object_like(analysis, type_name)) return 4;
	if (type_is_array(type_name)) {
		int dim = parse_array_dim(type_name);
		if (dim <= 0) dim = DEFAULT_INDEX_ELEMS;
		return dim * VM_WORD_SIZE;
	}
	if (strcmp(type_name, "bool") == 0 || strcmp(type_name, "byte") == 0 || strcmp(type_name, "char") == 0) return 1;
	return 4;
}

static char* make_var_label(const char* func_name, const char* var_name) {
	int len = snprintf(NULL, 0, "v_%s_%s", func_name ? func_name : "func", var_name ? var_name : "var") + 1;
	char* out = malloc((size_t)len);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(out, (size_t)len, "v_%s_%s", func_name ? func_name : "func", var_name ? var_name : "var");
	return out;
}

static char* make_object_label(const char* func_name, const char* var_name) {
	int len = snprintf(NULL, 0, "o_%s_%s", func_name ? func_name : "func", var_name ? var_name : "obj") + 1;
	char* out = malloc((size_t)len);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(out, (size_t)len, "o_%s_%s", func_name ? func_name : "func", var_name ? var_name : "obj");
	return out;
}

static void vartable_init(VarTable* vt) {
	memset(vt, 0, sizeof(*vt));
}

static int vartable_find(const VarTable* vt, const char* name) {
	for (int i = 0; i < vt->count; i++) {
		if (strcmp(vt->entries[i].name, name) == 0) return i;
	}
	return -1;
}

static void vartable_add(VarTable* vt, const CFG_Analysis* analysis, const char* func_name, const char* name, const char* type_name, int size, int is_ref, int is_auto_object) {
	int idx = vartable_find(vt, name);
	if (idx >= 0) {
		if (!vt->entries[idx].type && type_name) vt->entries[idx].type = xstrdup(type_name);
		if (size > vt->entries[idx].size) vt->entries[idx].size = size;
		if (is_ref) vt->entries[idx].is_ref = 1;
		if (is_auto_object) vt->entries[idx].is_auto_object = 1;
		return;
	}
	if (vt->count == vt->capacity) {
		int new_cap = vt->capacity ? vt->capacity * 2 : 16;
		VarEntry* p = realloc(vt->entries, (size_t)new_cap * sizeof(VarEntry));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		vt->entries = p;
		vt->capacity = new_cap;
	}
	VarEntry* e = &vt->entries[vt->count++];
	memset(e, 0, sizeof(*e));
	e->name = xstrdup(name);
	e->label = make_var_label(func_name, name);
	e->type = xstrdup(type_name);
	e->size = size > 0 ? size : 4;
	e->is_ref = is_ref ? 1 : 0;
	e->is_auto_object = is_auto_object ? 1 : 0;
	if (e->is_auto_object && type_is_object_like(analysis, type_name)) {
		const CFG_UserType* type = find_type(analysis, type_name);
		e->object_label = make_object_label(func_name, name);
		e->object_size = type ? type->object_word_size * VM_WORD_SIZE : VM_WORD_SIZE;
		e->type_id = type ? type->type_id : 0;
	}
}

static const VarEntry* vartable_get(const VarTable* vt, const char* name) {
	int idx = vartable_find(vt, name);
	return idx >= 0 ? &vt->entries[idx] : NULL;
}

static int vartable_total_size(const VarTable* vt) {
	int total = 0;
	for (int i = 0; i < vt->count; i++) {
		total += vt->entries[i].size;
		if (vt->entries[i].object_size > 0) total += vt->entries[i].object_size;
	}
	return total;
}

static void vartable_free(VarTable* vt) {
	for (int i = 0; i < vt->count; i++) {
		free(vt->entries[i].name);
		free(vt->entries[i].label);
		free(vt->entries[i].type);
		free(vt->entries[i].object_label);
	}
	free(vt->entries);
	memset(vt, 0, sizeof(*vt));
}

static void program_init(LC_Program* program) {
	memset(program, 0, sizeof(*program));
}

static int program_find_const(const LC_Program* program, IR_ConstKind kind, const char* value) {
	for (int i = 0; i < program->constant_count; i++) {
		if (program->constants[i].const_kind == kind && program->constants[i].value && strcmp(program->constants[i].value, value) == 0) {
			return i;
		}
	}
	return -1;
}

static int program_find_data(const LC_Program* program, const char* name) {
	for (int i = 0; i < program->data_count; i++) {
		if (strcmp(program->data[i].name, name) == 0) return i;
	}
	return -1;
}

static LC_DataItem* program_add_const(LC_Program* program, IR_ConstKind kind, const char* value) {
	int idx = program_find_const(program, kind, value);
	if (idx >= 0) return &program->constants[idx];
	if (program->constant_count == program->constant_capacity) {
		int new_cap = program->constant_capacity ? program->constant_capacity * 2 : 16;
		LC_DataItem* p = realloc(program->constants, (size_t)new_cap * sizeof(LC_DataItem));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		program->constants = p;
		program->constant_capacity = new_cap;
	}
	LC_DataItem* item = &program->constants[program->constant_count++];
	memset(item, 0, sizeof(*item));
	int name_len = snprintf(NULL, 0, "k%d", program->constant_count - 1) + 1;
	item->name = malloc((size_t)name_len);
	if (!item->name) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(item->name, (size_t)name_len, "k%d", program->constant_count - 1);
	item->kind = LC_DATA_CONST;
	item->const_kind = kind;
	item->value = xstrdup(value);
	return item;
}

static LC_DataItem* program_add_data(LC_Program* program, const char* name, int size) {
	int idx = program_find_data(program, name);
	if (idx >= 0) return &program->data[idx];
	if (program->data_count == program->data_capacity) {
		int new_cap = program->data_capacity ? program->data_capacity * 2 : 16;
		LC_DataItem* p = realloc(program->data, (size_t)new_cap * sizeof(LC_DataItem));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		program->data = p;
		program->data_capacity = new_cap;
	}
	LC_DataItem* item = &program->data[program->data_count++];
	memset(item, 0, sizeof(*item));
	item->name = xstrdup(name);
	item->kind = LC_DATA_VAR;
	item->size = size > 0 ? size : 4;
	return item;
}

static LC_CodeBlock* program_add_block(LC_Program* program, const char* name) {
	if (program->block_count == program->block_capacity) {
		int new_cap = program->block_capacity ? program->block_capacity * 2 : 32;
		LC_CodeBlock* p = realloc(program->blocks, (size_t)new_cap * sizeof(LC_CodeBlock));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		program->blocks = p;
		program->block_capacity = new_cap;
	}
	LC_CodeBlock* block = &program->blocks[program->block_count++];
	memset(block, 0, sizeof(*block));
	block->name = xstrdup(name);
	return block;
}

static void block_add_instr(LC_CodeBlock* block, const char* mnemonic, const char** operands, int operand_count) {
	if (block->instruction_count == block->instruction_capacity) {
		int new_cap = block->instruction_capacity ? block->instruction_capacity * 2 : 16;
		LC_Instruction* p = realloc(block->instructions, (size_t)new_cap * sizeof(LC_Instruction));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		block->instructions = p;
		block->instruction_capacity = new_cap;
	}
	LC_Instruction* ins = &block->instructions[block->instruction_count++];
	memset(ins, 0, sizeof(*ins));
	ins->mnemonic = xstrdup(mnemonic);
	ins->operand_count = operand_count;
	if (operand_count > 0) {
		ins->operands = malloc((size_t)operand_count * sizeof(char*));
		if (!ins->operands) {
			perror("malloc");
			exit(EXIT_FAILURE);
		}
		for (int i = 0; i < operand_count; i++) {
			ins->operands[i] = xstrdup(operands[i]);
		}
	}
}

static void block_add_instr0(LC_CodeBlock* block, const char* mnemonic) {
	block_add_instr(block, mnemonic, NULL, 0);
}

static void block_add_instr1(LC_CodeBlock* block, const char* mnemonic, const char* op1) {
	const char* ops[1] = { op1 };
	block_add_instr(block, mnemonic, ops, 1);
}

static void block_add_instr2(LC_CodeBlock* block, const char* mnemonic, const char* op1, const char* op2) {
	const char* ops[2] = { op1, op2 };
	block_add_instr(block, mnemonic, ops, 2);
}

static int guess_store_size(const IRNode* node) {
	if (!node || node->type != IR_NODE_STORE || node->child_count < 1) return 4;
	const IRNode* rhs = node->children[node->child_count - 1];
	if (!rhs || rhs->type != IR_NODE_CONST) return 4;
	switch (rhs->const_kind) {
	case IR_CONST_BOOL:
	case IR_CONST_CHAR:
		return 1;
	default:
		return 4;
	}
}

static int parse_const_index(const IRNode* node, int* out_value) {
	if (!node || node->type != IR_NODE_CONST || !node->text) return 0;
	if (strcmp(node->text, "true") == 0) {
		*out_value = 1;
		return 1;
	}
	if (strcmp(node->text, "false") == 0) {
		*out_value = 0;
		return 1;
	}
	char* end = NULL;
	long value = strtol(node->text, &end, 0);
	if (end && *end == '\0') {
		*out_value = (int)value;
		return 1;
	}
	return 0;
}

static int max_index_from_range(const IRNode* node, int* known) {
	*known = 0;
	if (!node) return 0;
	if (node->type == IR_NODE_RANGE && node->child_count >= 2) {
		int a = 0, b = 0;
		if (parse_const_index(node->children[0], &a) && parse_const_index(node->children[1], &b)) {
			*known = 1;
			return a > b ? a : b;
		}
		return 0;
	}
	if (node->type == IR_NODE_RANGE && node->child_count == 1) {
		int v = 0;
		if (parse_const_index(node->children[0], &v)) {
			*known = 1;
			return v;
		}
		return 0;
	}
	{
		int v = 0;
		if (parse_const_index(node, &v)) {
			*known = 1;
			return v;
		}
	}
	return 0;
}

static int guess_indexed_size(const IRNode* node) {
	int max_sum = 0;
	int any = 0;
	for (int i = 0; i < node->child_count; i++) {
		const IRNode* idx = node->children[i];
		if (!idx || idx->type != IR_NODE_INDEX || idx->child_count < 1) continue;
		int known = 0;
		int max_idx = max_index_from_range(idx->children[0], &known);
		if (!known) max_idx = DEFAULT_INDEX_ELEMS - 1;
		if (max_idx < 0) max_idx = 0;
		max_sum += max_idx;
		any = 1;
	}
	return any ? (max_sum + 1) * VM_WORD_SIZE : VM_WORD_SIZE;
}

static void collect_vars_ir(const IRNode* node, VarTable* vars, const CFG_Analysis* analysis, const CFG_Subprogram* sp) {
	if (!node) return;
	if ((node->type == IR_NODE_LOAD || node->type == IR_NODE_STORE || node->type == IR_NODE_DECL) && node->text) {
		int size = 4;
		int is_ref = 0;
		if (node->type_name && node->type_name[0] != '\0') {
			size = size_for_type_name(analysis, node->type_name);
			is_ref = type_is_array(node->type_name) || type_is_object_like(analysis, node->type_name);
		}
		else if (node->type == IR_NODE_STORE) {
			size = guess_store_size(node);
		}
		if (node->type == IR_NODE_LOAD || node->type == IR_NODE_STORE) {
			int has_index = 0;
			for (int i = 0; i < node->child_count; i++) {
				if (node->children[i] && node->children[i]->type == IR_NODE_INDEX) has_index = 1;
			}
			if (has_index) size = guess_indexed_size(node);
		}
		vartable_add(vars, analysis, sp->name, node->text, node->type_name, size, is_ref, (node->flags & 1) != 0);
	}
	for (int i = 0; i < node->child_count; i++) {
		collect_vars_ir(node->children[i], vars, analysis, sp);
	}
}

static IR_ConstKind guess_const_kind(const char* value) {
	if (!value) return IR_CONST_UNKNOWN;
	if (strcmp(value, "true") == 0 || strcmp(value, "false") == 0) return IR_CONST_BOOL;
	for (const char* p = value; *p; p++) {
		if (!isdigit((unsigned char)*p) && *p != '-' && *p != '+') return IR_CONST_STRING;
	}
	return IR_CONST_NUMBER;
}

static int emit_ir(EmitCtx* ctx, const IRNode* node);

static void emit_range(EmitCtx* ctx, const IRNode* range) {
	if (!range) return;
	if (range->type == IR_NODE_RANGE && range->child_count >= 2) {
		emit_ir(ctx, range->children[0]);
		emit_ir(ctx, range->children[1]);
		block_add_instr0(ctx->block, "RANGE_OP");
		return;
	}
	if (range->type == IR_NODE_RANGE && range->child_count >= 1) {
		emit_ir(ctx, range->children[0]);
		return;
	}
	emit_ir(ctx, range);
}

static void emit_index(EmitCtx* ctx, const IRNode* idx) {
	if (!idx) return;
	if (idx->type == IR_NODE_INDEX && idx->child_count >= 1) {
		emit_range(ctx, idx->children[0]);
		block_add_instr0(ctx->block, "INDEX");
	}
}

static int emit_load(EmitCtx* ctx, const IRNode* node) {
	const VarEntry* e = vartable_get(ctx->vars, node->text);
	if (!e) return 0;
	if (node->child_count == 0) {
		if (e->is_ref && !type_is_array(e->type)) {
			block_add_instr1(ctx->block, "LOAD", e->label);
			return 1;
		}
		if (type_is_array(e->type)) {
			block_add_instr1(ctx->block, e->is_ref ? "LOAD" : "PUSH_ADDR", e->label);
			return 1;
		}
		block_add_instr1(ctx->block, "LOAD", e->label);
		return 1;
	}
	block_add_instr1(ctx->block, e->is_ref ? "LOAD" : "PUSH_ADDR", e->label);
	for (int i = 0; i < node->child_count; i++) {
		emit_index(ctx, node->children[i]);
	}
	block_add_instr0(ctx->block, "LOAD_IND");
	return 1;
}

static int emit_load_address(EmitCtx* ctx, const IRNode* node) {
	const VarEntry* e = vartable_get(ctx->vars, node->text);
	if (!e) return 0;
	block_add_instr1(ctx->block, e->is_ref ? "LOAD" : "PUSH_ADDR", e->label);
	for (int i = 0; i < node->child_count; i++) {
		emit_index(ctx, node->children[i]);
	}
	return 1;
}

static void emit_field_address(EmitCtx* ctx, const IRNode* node) {
	emit_ir(ctx, node->children[0]);
	char offset_buf[32];
	snprintf(offset_buf, sizeof(offset_buf), "%d", node->offset);
	LC_DataItem* c = program_add_const(ctx->program, IR_CONST_NUMBER, offset_buf);
	block_add_instr1(ctx->block, "PUSH_CONST", c->name);
	block_add_instr0(ctx->block, "INDEX");
}

static int emit_store(EmitCtx* ctx, const IRNode* node) {
	const VarEntry* e = vartable_get(ctx->vars, node->text);
	if (!e || node->child_count == 0) return 0;
	if (node->child_count == 1 && node->children[0]->type != IR_NODE_INDEX) {
		emit_ir(ctx, node->children[0]);
		block_add_instr1(ctx->block, "STORE", e->label);
		return 0;
	}
	block_add_instr1(ctx->block, e->is_ref ? "LOAD" : "PUSH_ADDR", e->label);
	for (int i = 0; i < node->child_count - 1; i++) emit_index(ctx, node->children[i]);
	emit_ir(ctx, node->children[node->child_count - 1]);
	block_add_instr0(ctx->block, "STORE_IND");
	return 0;
}

static int emit_call(EmitCtx* ctx, const IRNode* node) {
	const CFG_Subprogram* callee = find_subprogram(ctx->analysis, node->text);
	for (int i = 0; i < node->child_count; i++) {
		int want_addr = 0;
		if (callee) {
			int param_idx = i;
			if (param_idx < callee->param_count) {
				want_addr = type_is_array(callee->params[param_idx].type);
			}
		}
		if (want_addr && node->children[i] && node->children[i]->type == IR_NODE_LOAD) {
			emit_load_address(ctx, node->children[i]);
		}
		else {
			emit_ir(ctx, node->children[i]);
		}
	}
	char argc_buf[32];
	snprintf(argc_buf, sizeof(argc_buf), "%d", node->child_count);
	block_add_instr2(ctx->block, "CALL", node->text, argc_buf);
	return 1;
}

static int emit_method_call(EmitCtx* ctx, const IRNode* node) {
	for (int i = 0; i < node->child_count; i++) emit_ir(ctx, node->children[i]);
	char argc_buf[32];
	snprintf(argc_buf, sizeof(argc_buf), "%d", node->child_count);
	block_add_instr2(ctx->block, "CALL", node->text, argc_buf);
	return 1;
}

static int emit_ir(EmitCtx* ctx, const IRNode* node) {
	if (!ctx || !node) return 0;
	switch (node->type) {
	case IR_NODE_CONST: {
		IR_ConstKind kind = node->const_kind != IR_CONST_UNKNOWN ? node->const_kind : guess_const_kind(node->text);
		LC_DataItem* c = program_add_const(ctx->program, kind, node->text ? node->text : "0");
		block_add_instr1(ctx->block, "PUSH_CONST", c->name);
		return 1;
	}
	case IR_NODE_LOAD:
		return emit_load(ctx, node);
	case IR_NODE_STORE:
		return emit_store(ctx, node);
	case IR_NODE_DECL:
		if (node->child_count >= 1) {
			const VarEntry* e = vartable_get(ctx->vars, node->text);
			if (e) {
				emit_ir(ctx, node->children[0]);
				block_add_instr1(ctx->block, "STORE", e->label);
			}
		}
		return 0;
	case IR_NODE_FIELD_LOAD:
		if (node->child_count < 1) return 0;
		emit_field_address(ctx, node);
		block_add_instr0(ctx->block, "LOAD_IND");
		return 1;
	case IR_NODE_FIELD_STORE:
		if (node->child_count < 2) return 0;
		emit_field_address(ctx, node);
		emit_ir(ctx, node->children[1]);
		block_add_instr0(ctx->block, "STORE_IND");
		return 0;
	case IR_NODE_UNARY:
		if (node->child_count >= 1) emit_ir(ctx, node->children[0]);
		if (node->op) block_add_instr0(ctx->block, node->op);
		return 1;
	case IR_NODE_BINARY:
		if (node->child_count >= 1) emit_ir(ctx, node->children[0]);
		if (node->child_count >= 2) emit_ir(ctx, node->children[1]);
		if (node->op) block_add_instr0(ctx->block, node->op);
		return 1;
	case IR_NODE_CALL:
		return emit_call(ctx, node);
	case IR_NODE_METHOD_CALL:
		return emit_method_call(ctx, node);
	case IR_NODE_RANGE:
		emit_range(ctx, node);
		return 1;
	case IR_NODE_INDEX:
		emit_index(ctx, node);
		return 1;
	case IR_NODE_ERROR:
		block_add_instr0(ctx->block, "NOP");
		return 0;
	default:
		return 0;
	}
}

static void intvec_free(IntVec* v) {
	free(v->data);
	memset(v, 0, sizeof(*v));
}

static int intvec_contains(const IntVec* v, int value) {
	for (int i = 0; i < v->count; i++) if (v->data[i] == value) return 1;
	return 0;
}

static void intvec_add_unique(IntVec* v, int value) {
	if (intvec_contains(v, value)) return;
	if (v->count == v->capacity) {
		int new_cap = v->capacity ? v->capacity * 2 : 8;
		int* p = realloc(v->data, (size_t)new_cap * sizeof(int));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		v->data = p;
		v->capacity = new_cap;
	}
	v->data[v->count++] = value;
}

static void scc_dfs(const CFG_Graph* g, int v, int* index, int* lowlink, int* stack, int* sp, int* onstack, int* index_gen, int* scc_id, int* scc_count) {
	index[v] = *index_gen;
	lowlink[v] = *index_gen;
	(*index_gen)++;
	stack[(*sp)++] = v;
	onstack[v] = 1;
	int succ[3] = { g->blocks[v].next, g->blocks[v].true_next, g->blocks[v].false_next };
	for (int i = 0; i < 3; i++) {
		int to = succ[i];
		if (to < 0 || to >= g->block_count) continue;
		if (index[to] == -1) {
			scc_dfs(g, to, index, lowlink, stack, sp, onstack, index_gen, scc_id, scc_count);
			if (lowlink[to] < lowlink[v]) lowlink[v] = lowlink[to];
		}
		else if (onstack[to] && index[to] < lowlink[v]) {
			lowlink[v] = index[to];
		}
	}
	if (lowlink[v] == index[v]) {
		while (*sp > 0) {
			int w = stack[--(*sp)];
			onstack[w] = 0;
			scc_id[w] = *scc_count;
			if (w == v) break;
		}
		(*scc_count)++;
	}
}

static void dfs_scc_order(const IntVec* edges, int scc, int* visited, int* postorder, int* count) {
	if (visited[scc]) return;
	visited[scc] = 1;
	for (int i = 0; i < edges[scc].count; i++) {
		dfs_scc_order(edges, edges[scc].data[i], visited, postorder, count);
	}
	postorder[(*count)++] = scc;
}

static void dfs_block_in_scc(const CFG_Graph* g, int id, int scc_target, const int* scc_id, int* visited, int* order, int* out_idx) {
	if (id < 0 || id >= g->block_count || visited[id] || scc_id[id] != scc_target) return;
	visited[id] = 1;
	order[(*out_idx)++] = id;
	int succ[3] = { g->blocks[id].next, g->blocks[id].true_next, g->blocks[id].false_next };
	for (int i = 0; i < 3; i++) {
		int to = succ[i];
		if (to >= 0 && to < g->block_count) dfs_block_in_scc(g, to, scc_target, scc_id, visited, order, out_idx);
	}
}

static int* cfg_block_order(const CFG_Graph* g, int* out_count) {
	int n = g->block_count;
	int* index = malloc((size_t)n * sizeof(int));
	int* lowlink = malloc((size_t)n * sizeof(int));
	int* stack = malloc((size_t)n * sizeof(int));
	int* onstack = calloc((size_t)n, sizeof(int));
	int* scc_id = malloc((size_t)n * sizeof(int));
	if (!index || !lowlink || !stack || !onstack || !scc_id) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < n; i++) {
		index[i] = -1;
		scc_id[i] = -1;
	}
	int sp = 0, index_gen = 0, scc_count = 0;
	for (int i = 0; i < n; i++) if (index[i] == -1) scc_dfs(g, i, index, lowlink, stack, &sp, onstack, &index_gen, scc_id, &scc_count);

	IntVec* scc_edges = calloc((size_t)scc_count, sizeof(IntVec));
	int* scc_visited = calloc((size_t)scc_count, sizeof(int));
	int* scc_postorder = malloc((size_t)scc_count * sizeof(int));
	if (!scc_edges || !scc_visited || !scc_postorder) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < n; i++) {
		int succ[3] = { g->blocks[i].next, g->blocks[i].true_next, g->blocks[i].false_next };
		for (int j = 0; j < 3; j++) {
			int to = succ[j];
			if (to < 0 || to >= n) continue;
			if (scc_id[i] != scc_id[to]) intvec_add_unique(&scc_edges[scc_id[i]], scc_id[to]);
		}
	}
	int scc_post_count = 0;
	if (g->entry_id >= 0) dfs_scc_order(scc_edges, scc_id[g->entry_id], scc_visited, scc_postorder, &scc_post_count);
	for (int i = 0; i < scc_count; i++) if (!scc_visited[i]) dfs_scc_order(scc_edges, i, scc_visited, scc_postorder, &scc_post_count);

	int* order = malloc((size_t)n * sizeof(int));
	int* block_visited = calloc((size_t)n, sizeof(int));
	if (!order || !block_visited) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	int out_idx = 0;
	for (int si = scc_post_count - 1; si >= 0; si--) {
		int scc = scc_postorder[si];
		if (g->entry_id >= 0 && scc_id[g->entry_id] == scc) dfs_block_in_scc(g, g->entry_id, scc, scc_id, block_visited, order, &out_idx);
		for (int i = 0; i < n; i++) if (scc_id[i] == scc && !block_visited[i]) dfs_block_in_scc(g, i, scc, scc_id, block_visited, order, &out_idx);
	}
	for (int i = 0; i < scc_count; i++) intvec_free(&scc_edges[i]);
	free(scc_edges);
	free(scc_visited);
	free(scc_postorder);
	free(block_visited);
	free(index);
	free(lowlink);
	free(stack);
	free(onstack);
	free(scc_id);
	*out_count = out_idx;
	return order;
}

static char* make_block_label(const CFG_Subprogram* sp, int id) {
	if (id == sp->cfg.entry_id) return xstrdup(sp->name);
	if (id == sp->cfg.exit_id) {
		int len = snprintf(NULL, 0, "%s_exit", sp->name) + 1;
		char* out = malloc((size_t)len);
		if (!out) {
			perror("malloc");
			exit(EXIT_FAILURE);
		}
		snprintf(out, (size_t)len, "%s_exit", sp->name);
		return out;
	}
	int len = snprintf(NULL, 0, "%s_B%d", sp->name, id) + 1;
	char* out = malloc((size_t)len);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(out, (size_t)len, "%s_B%d", sp->name, id);
	return out;
}

static void prepare_vartable_for_subprogram(VarTable* vars, LC_Program* program, const CFG_Subprogram* sp, const CFG_Analysis* analysis) {
	vartable_init(vars);
	for (int i = 0; i < sp->param_count; i++) {
		int is_ref = type_is_array(sp->params[i].type) || type_is_object_like(analysis, sp->params[i].type);
		int size = is_ref ? 4 : size_for_type_name(analysis, sp->params[i].type);
		vartable_add(vars, analysis, sp->name, sp->params[i].name, sp->params[i].type, size, is_ref, 0);
	}
	for (int i = 0; i < sp->symbol_count; i++) {
		if (sp->symbols[i].is_param) continue;
		int is_ref = type_is_array(sp->symbols[i].type) || type_is_object_like(analysis, sp->symbols[i].type);
		int size = is_ref ? 4 : size_for_type_name(analysis, sp->symbols[i].type);
		vartable_add(vars, analysis, sp->name, sp->symbols[i].name, sp->symbols[i].type, size, is_ref, sp->symbols[i].is_auto_object);
	}
	for (int i = 0; i < sp->cfg.block_count; i++) {
		collect_vars_ir(sp->cfg.blocks[i].ir, vars, analysis, sp);
	}
	for (int i = 0; i < vars->count; i++) {
		program_add_data(program, vars->entries[i].label, vars->entries[i].size);
		if (vars->entries[i].object_label) program_add_data(program, vars->entries[i].object_label, vars->entries[i].object_size);
	}
}

static void emit_auto_objects(EmitCtx* ctx) {
	for (int i = 0; i < ctx->vars->count; i++) {
		const VarEntry* e = &ctx->vars->entries[i];
		if (!e->is_auto_object || !e->object_label) continue;
		block_add_instr1(ctx->block, "PUSH_ADDR", e->object_label);
		block_add_instr1(ctx->block, "STORE", e->label);
		block_add_instr1(ctx->block, "PUSH_ADDR", e->object_label);
		char type_id_buf[32];
		snprintf(type_id_buf, sizeof(type_id_buf), "%d", e->type_id);
		LC_DataItem* c = program_add_const(ctx->program, IR_CONST_NUMBER, type_id_buf);
		block_add_instr1(ctx->block, "PUSH_CONST", c->name);
		block_add_instr0(ctx->block, "STORE_IND");
	}
}

static void generate_subprogram(LC_Program* program, const CFG_Subprogram* sp, const CFG_Analysis* analysis) {
	VarTable vars;
	prepare_vartable_for_subprogram(&vars, program, sp, analysis);

	char** labels = malloc((size_t)sp->cfg.block_count * sizeof(char*));
	if (!labels) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < sp->cfg.block_count; i++) labels[i] = make_block_label(sp, i);
	int order_count = 0;
	int* order = cfg_block_order(&sp->cfg, &order_count);

	for (int oi = 0; oi < order_count; oi++) {
		int id = order[oi];
		const CFG_Block* block = &sp->cfg.blocks[id];
		LC_CodeBlock* out_block = program_add_block(program, labels[id]);
		EmitCtx ctx = { program, &vars, out_block, sp, analysis };
		if (id == sp->cfg.entry_id) {
			for (int p = sp->param_count - 1; p >= 0; p--) {
				const VarEntry* e = vartable_get(&vars, sp->params[p].name);
				if (e) block_add_instr1(out_block, "STORE", e->label);
			}
			char locals_buf[32];
			snprintf(locals_buf, sizeof(locals_buf), "%d", vartable_total_size(&vars));
			block_add_instr1(out_block, "ENTER", locals_buf);
			emit_auto_objects(&ctx);
			if (block->next >= 0) block_add_instr1(out_block, "JMP", labels[block->next]);
			continue;
		}
		if (id == sp->cfg.exit_id) {
			const VarEntry* result_var = vartable_get(&vars, "result");
			if (!result_var && sp->method_name) result_var = vartable_get(&vars, sp->method_name);
			if (!result_var && sp->name) result_var = vartable_get(&vars, sp->name);
			if (result_var) {
				block_add_instr1(out_block, "LOAD", result_var->label);
			}
			else {
				LC_DataItem* zero = program_add_const(program, IR_CONST_NUMBER, "0");
				block_add_instr1(out_block, "PUSH_CONST", zero->name);
			}
			block_add_instr0(out_block, "LEAVE");
			block_add_instr0(out_block, (strcmp(sp->name, "main") == 0) ? "RET" : "RETF");
			continue;
		}
		int has_value = 0;
		if (block->ir) has_value = emit_ir(&ctx, block->ir);
		if (block->true_next >= 0 && block->false_next >= 0) {
			block_add_instr1(out_block, "JZ", labels[block->false_next]);
			block_add_instr1(out_block, "JMP", labels[block->true_next]);
			continue;
		}
		if (has_value) block_add_instr0(out_block, "POP");
		if (block->next >= 0) block_add_instr1(out_block, "JMP", labels[block->next]);
	}

	for (int i = 0; i < sp->cfg.block_count; i++) free(labels[i]);
	free(labels);
	free(order);
	vartable_free(&vars);
}

static void generate_dispatcher(LC_Program* program, const CFG_DispatchEntry* dispatch) {
	VarTable vars;
	vartable_init(&vars);
	vartable_add(&vars, NULL, dispatch->name, "self", dispatch->owner_type, 4, 1, 0);
	for (int i = 0; i < dispatch->param_count; i++) {
		int is_ref = type_is_array(dispatch->params[i].type);
		vartable_add(&vars, NULL, dispatch->name, dispatch->params[i].name, dispatch->params[i].type, is_ref ? 4 : dispatch->params[i].size, is_ref, 0);
	}
	for (int i = 0; i < vars.count; i++) {
		program_add_data(program, vars.entries[i].label, vars.entries[i].size);
	}

	LC_CodeBlock* entry = program_add_block(program, dispatch->name);
	for (int p = dispatch->param_count - 1; p >= 0; p--) {
		const VarEntry* e = vartable_get(&vars, dispatch->params[p].name);
		if (e) block_add_instr1(entry, "STORE", e->label);
	}
	{
		const VarEntry* self = vartable_get(&vars, "self");
		if (self) block_add_instr1(entry, "STORE", self->label);
	}
	{
		char locals_buf[32];
		snprintf(locals_buf, sizeof(locals_buf), "%d", vartable_total_size(&vars));
		block_add_instr1(entry, "ENTER", locals_buf);
	}

	char default_name[256];
	snprintf(default_name, sizeof(default_name), "%s_default", dispatch->name);

	if (dispatch->case_count == 0) {
		LC_DataItem* zero = program_add_const(program, IR_CONST_NUMBER, "0");
		block_add_instr1(entry, "PUSH_CONST", zero->name);
		block_add_instr0(entry, "LEAVE");
		block_add_instr0(entry, "RETF");
		vartable_free(&vars);
		return;
	}

	for (int i = 0; i < dispatch->case_count; i++) {
		char current_name[256];
		char next_name[256];
		if (i == 0) {
			snprintf(current_name, sizeof(current_name), "%s", dispatch->name);
		}
		else {
			snprintf(current_name, sizeof(current_name), "%s_check_%d", dispatch->name, i);
		}
		if (i + 1 < dispatch->case_count) {
			snprintf(next_name, sizeof(next_name), "%s_check_%d", dispatch->name, i + 1);
		}
		else {
			snprintf(next_name, sizeof(next_name), "%s", default_name);
		}

		LC_CodeBlock* check = (i == 0) ? entry : program_add_block(program, current_name);
		const VarEntry* self = vartable_get(&vars, "self");
		block_add_instr1(check, "LOAD", self->label);
		{
			LC_DataItem* zero = program_add_const(program, IR_CONST_NUMBER, "0");
			block_add_instr1(check, "PUSH_CONST", zero->name);
		}
		block_add_instr0(check, "INDEX");
		block_add_instr0(check, "LOAD_IND");
		{
			char type_id_buf[32];
			snprintf(type_id_buf, sizeof(type_id_buf), "%d", dispatch->cases[i].type_id);
			LC_DataItem* type_const = program_add_const(program, IR_CONST_NUMBER, type_id_buf);
			block_add_instr1(check, "PUSH_CONST", type_const->name);
		}
		block_add_instr0(check, "EQ");
		block_add_instr1(check, "JZ", next_name);
		block_add_instr1(check, "LOAD", self->label);
		for (int p = 0; p < dispatch->param_count; p++) {
			const VarEntry* e = vartable_get(&vars, dispatch->params[p].name);
			block_add_instr1(check, "LOAD", e->label);
		}
		{
			char argc_buf[32];
			snprintf(argc_buf, sizeof(argc_buf), "%d", dispatch->param_count + 1);
			block_add_instr2(check, "CALL", dispatch->cases[i].impl_name, argc_buf);
		}
		block_add_instr0(check, "LEAVE");
		block_add_instr0(check, "RETF");
	}
	LC_CodeBlock* def_block = program_add_block(program, default_name);
	LC_DataItem* zero = program_add_const(program, IR_CONST_NUMBER, "0");
	block_add_instr1(def_block, "PUSH_CONST", zero->name);
	block_add_instr0(def_block, "LEAVE");
	block_add_instr0(def_block, "RETF");
	vartable_free(&vars);
}

static char* escape_string(const char* s) {
	if (!s) return xstrdup("");
	size_t extra = 0;
	for (const char* p = s; *p; p++) {
		if (*p == '\\' || *p == '"' || *p == '\n' || *p == '\t' || *p == '\r') extra++;
	}
	char* out = malloc(strlen(s) + extra + 1);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	char* w = out;
	for (const char* p = s; *p; p++) {
		switch (*p) {
		case '\\': *w++ = '\\'; *w++ = '\\'; break;
		case '"': *w++ = '\\'; *w++ = '"'; break;
		case '\n': *w++ = '\\'; *w++ = 'n'; break;
		case '\t': *w++ = '\\'; *w++ = 't'; break;
		case '\r': *w++ = '\\'; *w++ = 'r'; break;
		default: *w++ = *p; break;
		}
	}
	*w = '\0';
	return out;
}

static void appendf(char** buf, size_t* len, size_t* cap, const char* fmt, ...) {
	va_list args;
	va_start(args, fmt);
	int needed = vsnprintf(NULL, 0, fmt, args);
	va_end(args);
	if (needed < 0) return;
	size_t add = (size_t)needed;
	if (*len + add + 1 > *cap) {
		size_t new_cap = *cap ? *cap : 256;
		while (*len + add + 1 > new_cap) new_cap *= 2;
		char* p = realloc(*buf, new_cap);
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		*buf = p;
		*cap = new_cap;
	}
	va_start(args, fmt);
	vsnprintf(*buf + *len, *cap - *len, fmt, args);
	va_end(args);
	*len += add;
}

static char* build_metadata_json(const CFG_Analysis* analysis) {
	char* buf = NULL;
	size_t len = 0;
	size_t cap = 0;
	appendf(&buf, &len, &cap, "{\"types\":[");
	for (int i = 0; i < analysis->type_count; i++) {
		const CFG_UserType* type = &analysis->types[i];
		char* name = escape_string(type->name);
		char* base = escape_string(type->base_name ? type->base_name : "");
		appendf(&buf, &len, &cap, "%s{\"name\":\"%s\",\"isInterface\":%s,\"typeId\":%d,\"base\":\"%s\",\"fields\":[",
			i ? "," : "", name, type->is_interface ? "true" : "false", type->type_id, base);
		for (int f = 0; f < type->field_count; f++) {
			char* field_name = escape_string(type->fields[f].name);
			char* field_type = escape_string(type->fields[f].type);
			appendf(&buf, &len, &cap, "%s{\"name\":\"%s\",\"type\":\"%s\",\"slot\":%d}",
				f ? "," : "", field_name, field_type, type->fields[f].slot_index);
			free(field_name);
			free(field_type);
		}
		appendf(&buf, &len, &cap, "]}");
		free(name);
		free(base);
	}
	appendf(&buf, &len, &cap, "],\"subprograms\":[");
	for (int i = 0; i < analysis->subprogram_count; i++) {
		const CFG_Subprogram* sp = &analysis->subprograms[i];
		char* name = escape_string(sp->name);
		appendf(&buf, &len, &cap, "%s{\"name\":\"%s\",\"symbols\":[", i ? "," : "", name);
		for (int s = 0; s < sp->symbol_count; s++) {
			const CFG_Symbol* sym = &sp->symbols[s];
			char* sym_name = escape_string(sym->name);
			char* sym_type = escape_string(sym->type ? sym->type : "");
			char* raw_label = make_var_label(sp->name, sym->name);
			char* label = escape_string(raw_label);
			appendf(&buf, &len, &cap, "%s{\"name\":\"%s\",\"label\":\"%s\",\"type\":\"%s\",\"isParam\":%s}",
				s ? "," : "", sym_name, label, sym_type, sym->is_param ? "true" : "false");
			free(sym_name);
			free(sym_type);
			free(raw_label);
			free(label);
		}
		appendf(&buf, &len, &cap, "]}");
		free(name);
	}
	appendf(&buf, &len, &cap, "]}");
	return buf;
}

LC_Program lc_generate_program(const CFG_Analysis* analysis) {
	LC_Program program;
	program_init(&program);
	if (!analysis) return program;
	for (int i = 0; i < analysis->subprogram_count; i++) {
		generate_subprogram(&program, &analysis->subprograms[i], analysis);
	}
	for (int i = 0; i < analysis->dispatcher_count; i++) {
		generate_dispatcher(&program, &analysis->dispatchers[i]);
	}
	program.metadata_json = build_metadata_json(analysis);
	return program;
}

static void write_const_item(FILE* f, const LC_DataItem* item) {
	switch (item->const_kind) {
	case IR_CONST_STRING: {
		char* esc = escape_string(item->value ? item->value : "");
		fprintf(f, "%s: DB \"%s\"\n", item->name, esc);
		free(esc);
		break;
	}
	case IR_CONST_CHAR:
		fprintf(f, "%s: DB %d\n", item->name, item->value && item->value[0] ? (unsigned char)item->value[0] : 0);
		break;
	case IR_CONST_BOOL:
		fprintf(f, "%s: DB %d\n", item->name, item->value && strcmp(item->value, "true") == 0 ? 1 : 0);
		break;
	default:
		fprintf(f, "%s: DD %s\n", item->name, item->value ? item->value : "0");
		break;
	}
}

static void write_data_item(FILE* f, const LC_DataItem* item) {
	int size = item->size > 0 ? item->size : 4;
	if (size == 1) fprintf(f, "%s: DB 0\n", item->name);
	else if (size == 4) fprintf(f, "%s: DD 0\n", item->name);
	else fprintf(f, "%s: RESB %d\n", item->name, size);
}

static int program_uses_call(const LC_Program* program, const char* name) {
	for (int b = 0; b < program->block_count; b++) {
		const LC_CodeBlock* block = &program->blocks[b];
		for (int i = 0; i < block->instruction_count; i++) {
			const LC_Instruction* ins = &block->instructions[i];
			if (ins->mnemonic && strcmp(ins->mnemonic, "CALL") == 0 && ins->operand_count >= 1 && strcmp(ins->operands[0], name) == 0) {
				return 1;
			}
		}
	}
	return 0;
}

static int block_is_main_family(const LC_CodeBlock* block) {
	const char* name = block ? block->name : NULL;
	return name && (strcmp(name, "main") == 0 || strncmp(name, "main_", 5) == 0 || strncmp(name, "mainB", 5) == 0 || strncmp(name, "main_B", 6) == 0);
}

static void write_code_block(FILE* f, const LC_CodeBlock* block) {
	fprintf(f, "%s:\n", block->name ? block->name : "block");
	for (int i = 0; i < block->instruction_count; i++) {
		const LC_Instruction* ins = &block->instructions[i];
		fprintf(f, "  %s", ins->mnemonic);
		if (ins->operand_count > 0) {
			fprintf(f, " %s", ins->operands[0]);
			for (int j = 1; j < ins->operand_count; j++) fprintf(f, ", %s", ins->operands[j]);
		}
		fprintf(f, "\n");
	}
	fprintf(f, "\n");
}

int lc_write_assembly(const LC_Program* program, const char* filename) {
	FILE* f = fopen(filename, "w");
	if (!f) return 0;

	fprintf(f, "; SPO5 linear code listing\n\n");
	fprintf(f, "[section const_pool]\n");
	if (program->constant_count == 0) fprintf(f, "; (empty)\n");
	for (int i = 0; i < program->constant_count; i++) write_const_item(f, &program->constants[i]);
	fprintf(f, "__builtin_zero: DD 0\n");
	fprintf(f, "__builtin_one: DD 1\n");

	fprintf(f, "\n[section data_mem]\n");
	if (program->data_count == 0) fprintf(f, "; (empty)\n");
	for (int i = 0; i < program->data_count; i++) write_data_item(f, &program->data[i]);

	fprintf(f, "\n[section data_meta]\n");
	fprintf(f, "__spo5_meta_magic: DB \"SPO5META\"\n");
	if (program->metadata_json) {
		char* esc = escape_string(program->metadata_json);
		fprintf(f, "__spo5_meta_json: DB \"%s\"\n", esc);
		free(esc);
	}

	fprintf(f, "\n[section code]\n");
	int has_main = 0;
	for (int b = 0; b < program->block_count; b++) {
		if (block_is_main_family(&program->blocks[b])) {
			has_main = 1;
			break;
		}
	}
	if (has_main) {
		for (int b = 0; b < program->block_count; b++) {
			if (block_is_main_family(&program->blocks[b])) write_code_block(f, &program->blocks[b]);
		}
		for (int b = 0; b < program->block_count; b++) {
			if (!block_is_main_family(&program->blocks[b])) write_code_block(f, &program->blocks[b]);
		}
	}
	else {
		for (int b = 0; b < program->block_count; b++) {
			write_code_block(f, &program->blocks[b]);
		}
	}

	if (program_uses_call(program, "print")) {
		fprintf(f, "print:\n");
		fprintf(f, "  PUSH_CONST __builtin_one\n");
		fprintf(f, "  SET_PORT\n");
		fprintf(f, "  OUT\n");
		fprintf(f, "  PUSH_CONST __builtin_zero\n");
		fprintf(f, "  RETF\n\n");
	}
	if (program_uses_call(program, "printf")) {
		fprintf(f, "printf:\n");
		fprintf(f, "  PUSH_CONST __builtin_one\n");
		fprintf(f, "  SET_PORT\n");
		fprintf(f, "  OUT\n");
		fprintf(f, "  PUSH_CONST __builtin_zero\n");
		fprintf(f, "  RETF\n\n");
	}
	if (program_uses_call(program, "read")) {
		fprintf(f, "read:\n");
		fprintf(f, "  PUSH_CONST __builtin_zero\n");
		fprintf(f, "  SET_PORT\n");
		fprintf(f, "  IN\n");
		fprintf(f, "  RETF\n\n");
	}

	fclose(f);
	return 1;
}

void lc_free_program(LC_Program* program) {
	if (!program) return;
	for (int i = 0; i < program->constant_count; i++) {
		free(program->constants[i].name);
		free(program->constants[i].value);
	}
	free(program->constants);
	for (int i = 0; i < program->data_count; i++) {
		free(program->data[i].name);
		free(program->data[i].value);
	}
	free(program->data);
	for (int i = 0; i < program->block_count; i++) {
		free(program->blocks[i].name);
		for (int j = 0; j < program->blocks[i].instruction_count; j++) {
			free(program->blocks[i].instructions[j].mnemonic);
			for (int k = 0; k < program->blocks[i].instructions[j].operand_count; k++) {
				free(program->blocks[i].instructions[j].operands[k]);
			}
			free(program->blocks[i].instructions[j].operands);
		}
		free(program->blocks[i].instructions);
	}
	free(program->blocks);
	free(program->metadata_json);
	memset(program, 0, sizeof(*program));
}
