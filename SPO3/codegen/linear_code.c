#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "linear_code.h"

typedef struct VarTable {
	char** names;
	char** labels;
	int* sizes;
	int* is_ref;
	int count;
	int capacity;
} VarTable;

typedef struct EmitCtx {
	LC_Program* program;
	VarTable* vars;
	LC_CodeBlock* block;
	const char* func_name;
	const CFG_Analysis* analysis;
} EmitCtx;

static int type_is_array(const char* type_str);
static const CFG_Subprogram* find_subprogram(const CFG_Analysis* analysis, const char* name);

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

static char* make_var_label(const char* func_name, const char* var_name) {
	const char* func = func_name ? func_name : "func";
	const char* var = var_name ? var_name : "var";
	int len = snprintf(NULL, 0, "v_%s_%s", func, var) + 1;
	char* res = malloc(len);
	if (!res) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(res, len, "v_%s_%s", func, var);
	return res;
}

static void vartable_init(VarTable* vt) {
	vt->names = NULL;
	vt->labels = NULL;
	vt->sizes = NULL;
	vt->is_ref = NULL;
	vt->count = 0;
	vt->capacity = 0;
}

static void vartable_free(VarTable* vt) {
	if (!vt) return;
	for (int i = 0; i < vt->count; i++) {
		free(vt->names[i]);
		free(vt->labels[i]);
	}
	free(vt->names);
	free(vt->labels);
	free(vt->sizes);
	free(vt->is_ref);
	vt->names = NULL;
	vt->labels = NULL;
	vt->sizes = NULL;
	vt->is_ref = NULL;
	vt->count = 0;
	vt->capacity = 0;
}

static int vartable_find(const VarTable* vt, const char* name) {
	if (!vt || !name) return -1;
	for (int i = 0; i < vt->count; i++) {
		if (strcmp(vt->names[i], name) == 0) return i;
	}
	return -1;
}

static void vartable_add(VarTable* vt, const char* name, const char* func_name, int size, int is_ref) {
	if (!vt || !name) return;
	int idx = vartable_find(vt, name);
	if (idx >= 0) {
		int new_size = size > 0 ? size : 4;
		if (new_size > vt->sizes[idx]) vt->sizes[idx] = new_size;
		if (is_ref) vt->is_ref[idx] = 1;
		return;
	}
	if (vt->count == vt->capacity) {
		int new_cap = vt->capacity ? vt->capacity * 2 : 16;
		char** n = realloc(vt->names, new_cap * sizeof(char*));
		char** l = realloc(vt->labels, new_cap * sizeof(char*));
		int* s = realloc(vt->sizes, new_cap * sizeof(int));
		int* r = realloc(vt->is_ref, new_cap * sizeof(int));
		if (!n || !l || !s || !r) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		vt->names = n;
		vt->labels = l;
		vt->sizes = s;
		vt->is_ref = r;
		vt->capacity = new_cap;
	}
	vt->names[vt->count] = xstrdup(name);
	vt->labels[vt->count] = make_var_label(func_name, name);
	vt->sizes[vt->count] = size > 0 ? size : 4;
	vt->is_ref[vt->count] = is_ref ? 1 : 0;
	vt->count++;
}

static const char* vartable_label(const VarTable* vt, const char* name) {
	int idx = vartable_find(vt, name);
	return (idx >= 0) ? vt->labels[idx] : NULL;
}

static int vartable_size(const VarTable* vt, const char* name) {
	int idx = vartable_find(vt, name);
	return (idx >= 0) ? vt->sizes[idx] : 4;
}

static int vartable_is_ref(const VarTable* vt, const char* name) {
	int idx = vartable_find(vt, name);
	return (idx >= 0) ? vt->is_ref[idx] : 0;
}

static int vartable_total_size(const VarTable* vt) {
	if (!vt) return 0;
	int total = 0;
	for (int i = 0; i < vt->count; i++) {
		total += vt->sizes[i] > 0 ? vt->sizes[i] : 4;
	}
	return total;
}

static void program_init(LC_Program* program) {
	memset(program, 0, sizeof(*program));
}

static int program_find_const(const LC_Program* program, IR_ConstKind kind, const char* value) {
	if (!program || !value) return -1;
	for (int i = 0; i < program->constant_count; i++) {
		const LC_DataItem* item = &program->constants[i];
		if (item->const_kind != kind) continue;
		if (item->value && strcmp(item->value, value) == 0) return i;
	}
	return -1;
}

static int program_find_data(const LC_Program* program, const char* name) {
	if (!program || !name) return -1;
	for (int i = 0; i < program->data_count; i++) {
		if (strcmp(program->data[i].name, name) == 0) return i;
	}
	return -1;
}

static LC_DataItem* program_add_const(LC_Program* program, IR_ConstKind kind, const char* value) {
	if (!program || !value) return NULL;
	int idx = program_find_const(program, kind, value);
	if (idx >= 0) return &program->constants[idx];

	if (program->constant_count == program->constant_capacity) {
		int new_cap = program->constant_capacity ? program->constant_capacity * 2 : 16;
		LC_DataItem* p = realloc(program->constants, new_cap * sizeof(LC_DataItem));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		program->constants = p;
		program->constant_capacity = new_cap;
	}

	int id = program->constant_count;
	LC_DataItem* item = &program->constants[id];
	memset(item, 0, sizeof(*item));

	int name_len = snprintf(NULL, 0, "k%d", id) + 1;
	item->name = malloc(name_len);
	if (!item->name) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(item->name, name_len, "k%d", id);

	item->kind = LC_DATA_CONST;
	item->const_kind = kind;
	item->value = xstrdup(value);
	item->size = 0;

	program->constant_count++;
	return item;
}

static LC_DataItem* program_add_data(LC_Program* program, const char* name, int size) {
	if (!program || !name) return NULL;
	int idx = program_find_data(program, name);
	if (idx >= 0) return &program->data[idx];

	if (program->data_count == program->data_capacity) {
		int new_cap = program->data_capacity ? program->data_capacity * 2 : 16;
		LC_DataItem* p = realloc(program->data, new_cap * sizeof(LC_DataItem));
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
	item->const_kind = IR_CONST_UNKNOWN;
	item->value = NULL;
	item->size = size;
	return item;
}

static LC_CodeBlock* program_add_block(LC_Program* program, const char* name) {
	if (!program || !name) return NULL;
	if (program->block_count == program->block_capacity) {
		int new_cap = program->block_capacity ? program->block_capacity * 2 : 32;
		LC_CodeBlock* p = realloc(program->blocks, new_cap * sizeof(LC_CodeBlock));
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
	if (!block || !mnemonic) return;
	if (block->instruction_count == block->instruction_capacity) {
		int new_cap = block->instruction_capacity ? block->instruction_capacity * 2 : 16;
		LC_Instruction* p = realloc(block->instructions, new_cap * sizeof(LC_Instruction));
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
		ins->operands = malloc(operand_count * sizeof(char*));
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
	case IR_CONST_STRING:
		return 4;
	case IR_CONST_NUMBER:
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
	if (node->const_kind == IR_CONST_CHAR && node->text[0]) {
		*out_value = (unsigned char)node->text[0];
		return 1;
	}
	char* end = NULL;
	long v = strtol(node->text, &end, 0);
	if (end && *end == '\0') {
		*out_value = (int)v;
		return 1;
	}
	return 0;
}

static int max_index_from_range(const IRNode* node, int* known) {
	*known = 0;
	if (!node) return 0;
	if (node->type == IR_NODE_RANGE) {
		if (node->child_count >= 2) {
			int a = 0;
			int b = 0;
			if (parse_const_index(node->children[0], &a) && parse_const_index(node->children[1], &b)) {
				*known = 1;
				return (a > b) ? a : b;
			}
			return 0;
		}
		if (node->child_count == 1) {
			int v = 0;
			if (parse_const_index(node->children[0], &v)) {
				*known = 1;
				return v;
			}
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

#define VM_WORD_SIZE 4
#define DEFAULT_INDEX_ELEMS 64

static int guess_indexed_size(const IRNode* node) {
	if (!node || node->child_count == 0) return 4;
	int max_sum = 0;
	int has_any = 0;
	for (int i = 0; i < node->child_count; i++) {
		const IRNode* idx = node->children[i];
		if (!idx || idx->type != IR_NODE_INDEX || idx->child_count < 1) {
			continue;
		}
		int known = 0;
		int max_idx = max_index_from_range(idx->children[0], &known);
		if (!known) {
			max_idx = DEFAULT_INDEX_ELEMS - 1;
		}
		if (max_idx < 0) max_idx = 0;
		max_sum += max_idx;
		has_any = 1;
	}
	if (!has_any) return 4;
	return (max_sum + 1) * 4;
}

static void collect_vars_ir(const IRNode* node, VarTable* vars, const char* func_name) {
	if (!node) return;
	if ((node->type == IR_NODE_LOAD || node->type == IR_NODE_STORE) && node->text) {
		int size = 4;
		int has_index = 0;
		for (int i = 0; i < node->child_count; i++) {
			if (node->children[i] && node->children[i]->type == IR_NODE_INDEX) {
				has_index = 1;
				break;
			}
		}
		if (has_index) {
			size = guess_indexed_size(node);
		}
		else if (node->type == IR_NODE_STORE) {
			size = guess_store_size(node);
		}
		vartable_add(vars, node->text, func_name, size, 0);
	}
	for (int i = 0; i < node->child_count; i++) {
		collect_vars_ir(node->children[i], vars, func_name);
	}
}

static IR_ConstKind guess_const_kind(const char* value) {
	if (!value) return IR_CONST_UNKNOWN;
	if (strcmp(value, "true") == 0 || strcmp(value, "false") == 0) return IR_CONST_BOOL;
	if (value[0] == '\0') return IR_CONST_UNKNOWN;
	if (value[0] == '0' && (value[1] == 'x' || value[1] == 'X' || value[1] == 'b' || value[1] == 'B')) {
		return IR_CONST_NUMBER;
	}
	for (const char* p = value; *p; p++) {
		if (!isdigit((unsigned char)*p) && *p != '-') return IR_CONST_STRING;
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
		return;
	}
	emit_ir(ctx, idx);
	block_add_instr0(ctx->block, "INDEX");
}

static int emit_load(EmitCtx* ctx, const IRNode* node) {
	const char* label = vartable_label(ctx->vars, node->text);
	if (!label) {
		int size = vartable_size(ctx->vars, node->text);
		vartable_add(ctx->vars, node->text, ctx->func_name, size, 0);
		label = vartable_label(ctx->vars, node->text);
		program_add_data(ctx->program, label ? label : node->text, size);
	}
	int is_ref = vartable_is_ref(ctx->vars, node->text);
	int is_array = vartable_size(ctx->vars, node->text) > 4 || is_ref;
	if (node->child_count == 0) {
		if (is_array) {
			if (is_ref) {
				block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
			}
			else {
				block_add_instr1(ctx->block, "PUSH_ADDR", label ? label : node->text);
			}
			return 1;
		}
		block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
		return 1;
	}
	if (is_ref) {
		block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
	}
	else {
		block_add_instr1(ctx->block, "PUSH_ADDR", label ? label : node->text);
	}
	for (int i = 0; i < node->child_count; i++) {
		emit_index(ctx, node->children[i]);
	}
	block_add_instr0(ctx->block, "LOAD_IND");
	return 1;
}

static int emit_load_address(EmitCtx* ctx, const IRNode* node) {
	const char* label = vartable_label(ctx->vars, node->text);
	if (!label) {
		int size = vartable_size(ctx->vars, node->text);
		vartable_add(ctx->vars, node->text, ctx->func_name, size, 0);
		label = vartable_label(ctx->vars, node->text);
		program_add_data(ctx->program, label ? label : node->text, size);
	}
	int is_ref = vartable_is_ref(ctx->vars, node->text);
	if (node->child_count == 0) {
		if (is_ref) {
			block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
		}
		else {
			block_add_instr1(ctx->block, "PUSH_ADDR", label ? label : node->text);
		}
		return 1;
	}
	if (is_ref) {
		block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
	}
	else {
		block_add_instr1(ctx->block, "PUSH_ADDR", label ? label : node->text);
	}
	for (int i = 0; i < node->child_count; i++) {
		emit_index(ctx, node->children[i]);
	}
	return 1;
}

static int emit_store(EmitCtx* ctx, const IRNode* node) {
	const char* label = vartable_label(ctx->vars, node->text);
	if (!label) {
		int size = vartable_size(ctx->vars, node->text);
		vartable_add(ctx->vars, node->text, ctx->func_name, size, 0);
		label = vartable_label(ctx->vars, node->text);
		program_add_data(ctx->program, label ? label : node->text, size);
	}
	int is_ref = vartable_is_ref(ctx->vars, node->text);
	if (node->child_count == 0) return 0;
	if (node->child_count == 1 && node->children[0]->type != IR_NODE_INDEX) {
		emit_ir(ctx, node->children[0]);
		block_add_instr1(ctx->block, "STORE", label ? label : node->text);
		return 0;
	}
	if (is_ref) {
		block_add_instr1(ctx->block, "LOAD", label ? label : node->text);
	}
	else {
		block_add_instr1(ctx->block, "PUSH_ADDR", label ? label : node->text);
	}
	for (int i = 0; i < node->child_count - 1; i++) {
		emit_index(ctx, node->children[i]);
	}
	emit_ir(ctx, node->children[node->child_count - 1]);
	block_add_instr0(ctx->block, "STORE_IND");
	return 0;
}

static int emit_ir(EmitCtx* ctx, const IRNode* node) {
	if (!ctx || !node) return 0;
	switch (node->type) {
	case IR_NODE_CONST: {
		IR_ConstKind kind = node->const_kind != IR_CONST_UNKNOWN ? node->const_kind : guess_const_kind(node->text);
		LC_DataItem* c = program_add_const(ctx->program, kind, node->text ? node->text : "0");
		if (c && c->name) {
			block_add_instr1(ctx->block, "PUSH_CONST", c->name);
		}
		return 1;
	}
	case IR_NODE_LOAD:
		return emit_load(ctx, node);
	case IR_NODE_STORE:
		return emit_store(ctx, node);
	case IR_NODE_UNARY:
		if (node->child_count >= 1) emit_ir(ctx, node->children[0]);
		if (node->op) block_add_instr0(ctx->block, node->op);
		return 1;
	case IR_NODE_BINARY:
		if (node->child_count >= 1) emit_ir(ctx, node->children[0]);
		if (node->child_count >= 2) emit_ir(ctx, node->children[1]);
		if (node->op) block_add_instr0(ctx->block, node->op);
		return 1;
	case IR_NODE_CALL: {
		const CFG_Subprogram* callee = find_subprogram(ctx->analysis, node->text);
		for (int i = 0; i < node->child_count; i++) {
			int want_addr = 0;
			if (callee && i < callee->param_count) {
				want_addr = type_is_array(callee->params[i].type);
			}
			int child_has_value = 0;
			if (want_addr && node->children[i] && node->children[i]->type == IR_NODE_LOAD) {
				child_has_value = emit_load_address(ctx, node->children[i]);
			}
			else {
				child_has_value = emit_ir(ctx, node->children[i]);
			}
			if (!child_has_value) {
				LC_DataItem* zero = program_add_const(ctx->program, IR_CONST_NUMBER, "0");
				if (zero && zero->name) {
					block_add_instr1(ctx->block, "PUSH_CONST", zero->name);
				}
			}
		}
		char argc_buf[32];
		snprintf(argc_buf, sizeof(argc_buf), "%d", node->child_count);
		block_add_instr2(ctx->block, "CALL", node->text ? node->text : "call", argc_buf);
		return 1;
	}
	case IR_NODE_RANGE:
		emit_range(ctx, node);
		return 1;
	case IR_NODE_INDEX:
		emit_index(ctx, node);
		return 1;
	case IR_NODE_LIST: {
		int has_value = 0;
		for (int i = 0; i < node->child_count; i++) {
			int child_has = emit_ir(ctx, node->children[i]);
			if (i + 1 < node->child_count && child_has) {
				block_add_instr0(ctx->block, "POP");
			}
			has_value = child_has;
		}
		return has_value;
	}
	case IR_NODE_ERROR:
		block_add_instr0(ctx->block, "NOP");
		return 0;
	default:
		return 0;
	}
}

typedef struct IntVec {
	int* data;
	int count;
	int capacity;
} IntVec;

static void intvec_free(IntVec* v) {
	free(v->data);
	v->data = NULL;
	v->count = 0;
	v->capacity = 0;
}

static int intvec_contains(const IntVec* v, int value) {
	for (int i = 0; i < v->count; i++) {
		if (v->data[i] == value) return 1;
	}
	return 0;
}

static void intvec_add_unique(IntVec* v, int value) {
	if (intvec_contains(v, value)) return;
	if (v->count == v->capacity) {
		int new_cap = v->capacity ? v->capacity * 2 : 8;
		int* p = realloc(v->data, new_cap * sizeof(int));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		v->data = p;
		v->capacity = new_cap;
	}
	v->data[v->count++] = value;
}

static void scc_dfs(const CFG_Graph* g, int v, int* index, int* lowlink, int* stack, int* sp,
					int* onstack, int* index_gen, int* scc_id, int* scc_count) {
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
		else if (onstack[to]) {
			if (index[to] < lowlink[v]) lowlink[v] = index[to];
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
		int to = edges[scc].data[i];
		if (!visited[to]) dfs_scc_order(edges, to, visited, postorder, count);
	}
	postorder[(*count)++] = scc;
}

static void dfs_block_in_scc(const CFG_Graph* g, int id, int scc_target, const int* scc_id,
							 int* visited, int* order, int* out_idx) {
	if (id < 0 || id >= g->block_count) return;
	if (visited[id]) return;
	if (scc_id[id] != scc_target) return;
	visited[id] = 1;
	order[(*out_idx)++] = id;

	int succ[3] = { g->blocks[id].next, g->blocks[id].true_next, g->blocks[id].false_next };
	for (int i = 0; i < 3; i++) {
		int to = succ[i];
		if (to >= 0 && to < g->block_count) {
			dfs_block_in_scc(g, to, scc_target, scc_id, visited, order, out_idx);
		}
	}
}

static int* cfg_block_order(const CFG_Graph* g, int* out_count) {
	int n = g->block_count;
	int* index = malloc(n * sizeof(int));
	int* lowlink = malloc(n * sizeof(int));
	int* stack = malloc(n * sizeof(int));
	int* onstack = calloc(n, sizeof(int));
	int* scc_id = malloc(n * sizeof(int));
	if (!index || !lowlink || !stack || !onstack || !scc_id) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < n; i++) {
		index[i] = -1;
		scc_id[i] = -1;
	}

	int sp = 0;
	int index_gen = 0;
	int scc_count = 0;
	for (int i = 0; i < n; i++) {
		if (index[i] == -1) {
			scc_dfs(g, i, index, lowlink, stack, &sp, onstack, &index_gen, scc_id, &scc_count);
		}
	}

	IntVec* scc_edges = calloc(scc_count, sizeof(IntVec));
	if (!scc_edges) {
		perror("calloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < n; i++) {
		int from = scc_id[i];
		int succ[3] = { g->blocks[i].next, g->blocks[i].true_next, g->blocks[i].false_next };
		for (int j = 0; j < 3; j++) {
			int to_id = succ[j];
			if (to_id < 0 || to_id >= n) continue;
			int to = scc_id[to_id];
			if (from != to) intvec_add_unique(&scc_edges[from], to);
		}
	}

	int* scc_visited = calloc(scc_count, sizeof(int));
	int* scc_postorder = malloc(scc_count * sizeof(int));
	if (!scc_visited || !scc_postorder) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	int scc_post_count = 0;

	if (g->entry_id >= 0) {
		int entry_scc = scc_id[g->entry_id];
		if (entry_scc >= 0) dfs_scc_order(scc_edges, entry_scc, scc_visited, scc_postorder, &scc_post_count);
	}
	for (int i = 0; i < scc_count; i++) {
		if (!scc_visited[i]) dfs_scc_order(scc_edges, i, scc_visited, scc_postorder, &scc_post_count);
	}

	int* scc_topo = malloc(scc_post_count * sizeof(int));
	if (!scc_topo) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < scc_post_count; i++) {
		scc_topo[i] = scc_postorder[scc_post_count - 1 - i];
	}

	int* order = malloc(n * sizeof(int));
	int* block_visited = calloc(n, sizeof(int));
	if (!order || !block_visited) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	int out_idx = 0;
	for (int si = 0; si < scc_post_count; si++) {
		int scc = scc_topo[si];
		int start = -1;
		if (g->entry_id >= 0 && scc_id[g->entry_id] == scc) start = g->entry_id;
		if (start >= 0) {
			dfs_block_in_scc(g, start, scc, scc_id, block_visited, order, &out_idx);
		}
		for (int i = 0; i < n; i++) {
			if (scc_id[i] == scc && !block_visited[i]) {
				dfs_block_in_scc(g, i, scc, scc_id, block_visited, order, &out_idx);
			}
		}
	}

	for (int i = 0; i < scc_count; i++) intvec_free(&scc_edges[i]);
	free(scc_edges);
	free(scc_visited);
	free(scc_postorder);
	free(scc_topo);
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
	const char* func = sp && sp->name ? sp->name : "func";
	if (sp && id == sp->cfg.entry_id) {
		return xstrdup(func);
	}
	if (sp && id == sp->cfg.exit_id) {
		int len = snprintf(NULL, 0, "%s_exit", func) + 1;
		char* res = malloc(len);
		if (!res) {
			perror("malloc");
			exit(EXIT_FAILURE);
		}
		snprintf(res, len, "%s_exit", func);
		return res;
	}
	int len = snprintf(NULL, 0, "%s_B%d", func, id) + 1;
	char* res = malloc(len);
	if (!res) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(res, len, "%s_B%d", func, id);
	return res;
}

static int param_size_for_name(const CFG_Subprogram* sp, const char* name) {
	if (!sp || !name) return 4;
	for (int i = 0; i < sp->param_count; i++) {
		if (sp->params[i].name && strcmp(sp->params[i].name, name) == 0) {
			return sp->params[i].size > 0 ? sp->params[i].size : 4;
		}
	}
	return 4;
}

static int type_is_array(const char* type_str) {
	return type_str && strstr(type_str, "array[") != NULL;
}

static int parse_array_dim(const char* type_str) {
	if (!type_str) return 0;
	const char* start = strstr(type_str, "array[");
	if (!start) return 0;
	start += strlen("array[");
	char* end = NULL;
	long dim = strtol(start, &end, 0);
	if (!end || *end != ']') return 0;
	if (dim <= 0) return 0;
	return (int)dim;
}

static int array_param_size_bytes(const char* type_str) {
	int dim = parse_array_dim(type_str);
	if (dim <= 0) dim = DEFAULT_INDEX_ELEMS;
	return dim * VM_WORD_SIZE;
}

static const CFG_Subprogram* find_subprogram(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return NULL;
	for (int i = 0; i < analysis->subprogram_count; i++) {
		if (analysis->subprograms[i].name && strcmp(analysis->subprograms[i].name, name) == 0) {
			return &analysis->subprograms[i];
		}
	}
	return NULL;
}

static void mark_array_args_ir(const CFG_Analysis* analysis, const IRNode* node, VarTable* vars, const char* func_name) {
	if (!node || !vars) return;
	if (node->type == IR_NODE_CALL && node->text) {
		const CFG_Subprogram* callee = find_subprogram(analysis, node->text);
		if (callee) {
			int n = node->child_count < callee->param_count ? node->child_count : callee->param_count;
			for (int i = 0; i < n; i++) {
				if (!type_is_array(callee->params[i].type)) continue;
				const IRNode* arg = node->children[i];
				if (!arg || arg->type != IR_NODE_LOAD || arg->child_count != 0 || !arg->text) continue;
				if (vartable_is_ref(vars, arg->text)) continue;
				int size = array_param_size_bytes(callee->params[i].type);
				vartable_add(vars, arg->text, func_name, size, 0);
			}
		}
	}
	for (int i = 0; i < node->child_count; i++) {
		mark_array_args_ir(analysis, node->children[i], vars, func_name);
	}
}

static void generate_subprogram(LC_Program* program, const CFG_Subprogram* sp, const CFG_Analysis* analysis) {
	if (!program || !sp) return;

	VarTable vars;
	vartable_init(&vars);
	for (int i = 0; i < sp->param_count; i++) {
		if (sp->params[i].name) {
			int is_ref = type_is_array(sp->params[i].type);
			int size = is_ref ? 4 : param_size_for_name(sp, sp->params[i].name);
			vartable_add(&vars, sp->params[i].name, sp->name, size, is_ref);
		}
	}
	for (int i = 0; i < sp->cfg.block_count; i++) {
		collect_vars_ir(sp->cfg.blocks[i].ir, &vars, sp->name);
		mark_array_args_ir(analysis, sp->cfg.blocks[i].ir, &vars, sp->name);
	}

	for (int i = 0; i < vars.count; i++) {
		program_add_data(program, vars.labels[i], vars.sizes[i]);
	}

	const char* ret_label = vartable_label(&vars, "result");
	if (!ret_label && sp->name) ret_label = vartable_label(&vars, sp->name);

	char** labels = malloc(sp->cfg.block_count * sizeof(char*));
	if (!labels) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < sp->cfg.block_count; i++) {
		labels[i] = make_block_label(sp, i);
	}

	int order_count = 0;
	int* order = cfg_block_order(&sp->cfg, &order_count);

	for (int oi = 0; oi < order_count; oi++) {
		int id = order[oi];
		const CFG_Block* block = &sp->cfg.blocks[id];
		LC_CodeBlock* out_block = program_add_block(program, labels[id]);
		EmitCtx ctx = {
			.program = program,
			.vars = &vars,
			.block = out_block,
			.func_name = sp->name,
			.analysis = analysis,
		};

		if (id == sp->cfg.entry_id) {
			char locals_buf[32];
			for (int p = sp->param_count - 1; p >= 0; p--) {
				const char* label = vartable_label(&vars, sp->params[p].name);
				if (label) block_add_instr1(out_block, "STORE", label);
			}
			snprintf(locals_buf, sizeof(locals_buf), "%d", vartable_total_size(&vars));
			block_add_instr1(out_block, "ENTER", locals_buf);
			if (block->next >= 0) {
				block_add_instr1(out_block, "JMP", labels[block->next]);
			}
			continue;
		}

		if (id == sp->cfg.exit_id) {
			const char* ret_mnemonic = (sp->name && strcmp(sp->name, "main") == 0) ? "RET" : "RETF";
			if (ret_label) {
				block_add_instr1(out_block, "LOAD", ret_label);
			}
			else {
				LC_DataItem* zero = program_add_const(program, IR_CONST_NUMBER, "0");
				if (zero && zero->name) {
					block_add_instr1(out_block, "PUSH_CONST", zero->name);
				}
			}
			block_add_instr0(out_block, "LEAVE");
			block_add_instr0(out_block, ret_mnemonic);
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
		if (block->next >= 0) {
			block_add_instr1(out_block, "JMP", labels[block->next]);
		}
	}

	for (int i = 0; i < sp->cfg.block_count; i++) {
		free(labels[i]);
	}
	free(labels);
	free(order);
	vartable_free(&vars);
}

LC_Program lc_generate_program(const CFG_Analysis* analysis) {
	LC_Program program;
	program_init(&program);
	if (!analysis) return program;

	for (int i = 0; i < analysis->subprogram_count; i++) {
		generate_subprogram(&program, &analysis->subprograms[i], analysis);
	}
	return program;
}

static char* escape_string(const char* s) {
	if (!s) return xstrdup("");
	size_t extra = 0;
	for (const char* p = s; *p; p++) {
		if (*p == '\\' || *p == '\"' || *p == '\n' || *p == '\t') extra++;
	}
	size_t len = strlen(s) + extra + 1;
	char* out = malloc(len);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	char* w = out;
	for (const char* p = s; *p; p++) {
		if (*p == '\\') {
			*w++ = '\\';
			*w++ = '\\';
		}
		else if (*p == '\"') {
			*w++ = '\\';
			*w++ = '\"';
		}
		else if (*p == '\n') {
			*w++ = '\\';
			*w++ = 'n';
		}
		else if (*p == '\t') {
			*w++ = '\\';
			*w++ = 't';
		}
		else {
			*w++ = *p;
		}
	}
	*w = '\0';
	return out;
}

static void write_const_item(FILE* f, const LC_DataItem* item) {
	if (!f || !item) return;
	switch (item->const_kind) {
	case IR_CONST_STRING: {
		char* esc = escape_string(item->value ? item->value : "");
		fprintf(f, "%s: DB \"%s\"\n", item->name, esc);
		free(esc);
		break;
	}
	case IR_CONST_CHAR: {
		char c = (item->value && item->value[0]) ? item->value[0] : '\0';
		if (c == '\'' || c == '\\') {
			fprintf(f, "%s: DB '\\%c'\n", item->name, c);
		}
		else if (c == '\n') {
			fprintf(f, "%s: DB '\\n'\n", item->name);
		}
		else if (c == '\t') {
			fprintf(f, "%s: DB '\\t'\n", item->name);
		}
		else {
			fprintf(f, "%s: DB '%c'\n", item->name, c ? c : ' ');
		}
		break;
	}
	case IR_CONST_BOOL: {
		int v = (item->value && strcmp(item->value, "true") == 0) ? 1 : 0;
		fprintf(f, "%s: DB %d\n", item->name, v);
		break;
	}
	case IR_CONST_NUMBER:
		fprintf(f, "%s: DD %s\n", item->name, item->value ? item->value : "0");
		break;
	default:
		fprintf(f, "%s: DD %s\n", item->name, item->value ? item->value : "0");
		break;
	}
}

static void write_data_item(FILE* f, const LC_DataItem* item) {
	if (!f || !item) return;
	int size = item->size > 0 ? item->size : 4;
	if (size == 1) {
		fprintf(f, "%s: DB 0\n", item->name);
	}
	else if (size == 4) {
		fprintf(f, "%s: DD 0\n", item->name);
	}
	else {
		fprintf(f, "%s: RESB %d\n", item->name, size);
	}
}

static int program_uses_call(const LC_Program* program, const char* name) {
	if (!program || !name) return 0;
	for (int b = 0; b < program->block_count; b++) {
		const LC_CodeBlock* block = &program->blocks[b];
		for (int i = 0; i < block->instruction_count; i++) {
			const LC_Instruction* ins = &block->instructions[i];
			if (!ins->mnemonic || strcmp(ins->mnemonic, "CALL") != 0) continue;
			if (ins->operand_count < 1 || !ins->operands[0]) continue;
			if (strcmp(ins->operands[0], name) == 0) return 1;
		}
	}
	return 0;
}

int lc_write_assembly(const LC_Program* program, const char* filename) {
	if (!program || !filename) return 0;
	FILE* f = fopen(filename, "w");
	if (!f) return 0;

	int need_print = program_uses_call(program, "print");
	int need_printf = program_uses_call(program, "printf");
	int need_read = program_uses_call(program, "read");
	int need_builtin_consts = need_print || need_printf || need_read;

	fprintf(f, "; SPO3 linear code listing\n");
	fprintf(f, "; VM: stack-based, memory banks: code, const_pool, data_mem, stack_mem\n\n");

	fprintf(f, "[section const_pool]\n");
	if (program->constant_count == 0) {
		fprintf(f, "; (empty)\n");
	}
	for (int i = 0; i < program->constant_count; i++) {
		write_const_item(f, &program->constants[i]);
	}
	if (need_builtin_consts) {
		fprintf(f, "__builtin_zero: DD 0\n");
		fprintf(f, "__builtin_one: DD 1\n");
	}

	fprintf(f, "\n[section data_mem]\n");
	if (program->data_count == 0) {
		fprintf(f, "; (empty)\n");
	}
	for (int i = 0; i < program->data_count; i++) {
		write_data_item(f, &program->data[i]);
	}

	fprintf(f, "\n[section code]\n");
	int has_main = 0;
	for (int b = 0; b < program->block_count; b++) {
		const char* name = program->blocks[b].name;
		if (name && (strcmp(name, "main") == 0 || strncmp(name, "main_", 5) == 0)) {
			has_main = 1;
			break;
		}
	}
	for (int pass = 0; pass < (has_main ? 2 : 1); pass++) {
		for (int b = 0; b < program->block_count; b++) {
			const LC_CodeBlock* block = &program->blocks[b];
			const char* name = block->name;
			int is_main = name && (strcmp(name, "main") == 0 || strncmp(name, "main_", 5) == 0);
			if (has_main && ((pass == 0 && !is_main) || (pass == 1 && is_main))) continue;
			fprintf(f, "%s:\n", name ? name : "block");
			for (int i = 0; i < block->instruction_count; i++) {
				const LC_Instruction* ins = &block->instructions[i];
				fprintf(f, "  %s", ins->mnemonic ? ins->mnemonic : "NOP");
				if (ins->operand_count > 0) {
					fprintf(f, " %s", ins->operands[0]);
					for (int j = 1; j < ins->operand_count; j++) {
						fprintf(f, ", %s", ins->operands[j]);
					}
				}
				fprintf(f, "\n");
			}
			fprintf(f, "\n");
		}
	}
	if (need_print || need_printf || need_read) {
		fprintf(f, "; builtins\n");
	}
	if (need_print) {
		fprintf(f, "print:\n");
		fprintf(f, "  PUSH_CONST __builtin_one\n");
		fprintf(f, "  SET_PORT\n");
		fprintf(f, "  OUT\n");
		fprintf(f, "  PUSH_CONST __builtin_zero\n");
		fprintf(f, "  RETF\n\n");
	}
	if (need_printf) {
		fprintf(f, "printf:\n");
		fprintf(f, "  PUSH_CONST __builtin_one\n");
		fprintf(f, "  SET_PORT\n");
		fprintf(f, "  OUT\n");
		fprintf(f, "  PUSH_CONST __builtin_zero\n");
		fprintf(f, "  RETF\n\n");
	}
	if (need_read) {
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
	program->constants = NULL;
	program->constant_count = 0;
	program->constant_capacity = 0;

	for (int i = 0; i < program->data_count; i++) {
		free(program->data[i].name);
		free(program->data[i].value);
	}
	free(program->data);
	program->data = NULL;
	program->data_count = 0;
	program->data_capacity = 0;

	for (int i = 0; i < program->block_count; i++) {
		LC_CodeBlock* block = &program->blocks[i];
		for (int j = 0; j < block->instruction_count; j++) {
			LC_Instruction* ins = &block->instructions[j];
			free(ins->mnemonic);
			for (int k = 0; k < ins->operand_count; k++) {
				free(ins->operands[k]);
			}
			free(ins->operands);
		}
		free(block->instructions);
		free(block->name);
	}
	free(program->blocks);
	program->blocks = NULL;
	program->block_count = 0;
	program->block_capacity = 0;
}
