#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "cfg.h"

typedef struct CFG_ExitList {
	int* ids;
	int count;
	int capacity;
} CFG_ExitList;

typedef struct CFG_Fragment {
	int entry;
	CFG_ExitList exits;
} CFG_Fragment;

typedef struct CFG_Builder {
	CFG_Graph* graph;
	CFG_Analysis* analysis;
	const char* filename;
	const CFG_Subprogram* subprogram;
	int func_exit_id;
} CFG_Builder;

typedef struct PendingType {
	const char* filename;
	AST_Node* node;
} PendingType;

typedef struct PendingTypeList {
	PendingType* items;
	int count;
	int capacity;
} PendingTypeList;

typedef struct PendingSubprogram {
	const char* filename;
	AST_Node* func_def;
	char* owner_type;
	int is_method;
	int is_override;
} PendingSubprogram;

typedef struct PendingSubprogramList {
	PendingSubprogram* items;
	int count;
	int capacity;
} PendingSubprogramList;

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

static void exit_list_init(CFG_ExitList* list) {
	list->ids = NULL;
	list->count = 0;
	list->capacity = 0;
}

static void exit_list_free(CFG_ExitList* list) {
	free(list->ids);
	list->ids = NULL;
	list->count = 0;
	list->capacity = 0;
}

static void exit_list_add(CFG_ExitList* list, int id) {
	if (list->count == list->capacity) {
		int new_cap = list->capacity ? list->capacity * 2 : 8;
		int* p = realloc(list->ids, (size_t)new_cap * sizeof(int));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		list->ids = p;
		list->capacity = new_cap;
	}
	list->ids[list->count++] = id;
}

static void exit_list_move(CFG_ExitList* dst, CFG_ExitList* src) {
	*dst = *src;
	src->ids = NULL;
	src->count = 0;
	src->capacity = 0;
}

static CFG_Fragment fragment_empty(void) {
	CFG_Fragment f;
	f.entry = -1;
	exit_list_init(&f.exits);
	return f;
}

static void pending_type_add(PendingTypeList* list, const char* filename, AST_Node* node) {
	if (list->count == list->capacity) {
		int new_cap = list->capacity ? list->capacity * 2 : 8;
		PendingType* p = realloc(list->items, (size_t)new_cap * sizeof(PendingType));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		list->items = p;
		list->capacity = new_cap;
	}
	list->items[list->count].filename = filename;
	list->items[list->count].node = node;
	list->count++;
}

static void pending_subprogram_add(PendingSubprogramList* list, const char* filename, AST_Node* func_def, const char* owner_type, int is_method, int is_override) {
	if (list->count == list->capacity) {
		int new_cap = list->capacity ? list->capacity * 2 : 16;
		PendingSubprogram* p = realloc(list->items, (size_t)new_cap * sizeof(PendingSubprogram));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		list->items = p;
		list->capacity = new_cap;
	}
	list->items[list->count].filename = filename;
	list->items[list->count].func_def = func_def;
	list->items[list->count].owner_type = xstrdup(owner_type);
	list->items[list->count].is_method = is_method;
	list->items[list->count].is_override = is_override;
	list->count++;
}

static void pending_subprograms_free(PendingSubprogramList* list) {
	for (int i = 0; i < list->count; i++) {
		free(list->items[i].owner_type);
	}
	free(list->items);
	list->items = NULL;
	list->count = 0;
	list->capacity = 0;
}

static void analysis_add_error(CFG_Analysis* analysis, const char* filename, int line, int column, const char* fmt, ...) {
	if (analysis->error_count == analysis->error_capacity) {
		int new_cap = analysis->error_capacity ? analysis->error_capacity * 2 : 16;
		CFG_Error* p = realloc(analysis->errors, (size_t)new_cap * sizeof(CFG_Error));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		analysis->errors = p;
		analysis->error_capacity = new_cap;
	}

	va_list args;
	va_start(args, fmt);
	int msg_len = vsnprintf(NULL, 0, fmt, args) + 1;
	va_end(args);

	char* msg = malloc((size_t)msg_len);
	if (!msg) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	va_start(args, fmt);
	vsnprintf(msg, (size_t)msg_len, fmt, args);
	va_end(args);

	CFG_Error* err = &analysis->errors[analysis->error_count++];
	err->filename = filename ? xstrdup(filename) : NULL;
	err->line = line;
	err->column = column;
	err->message = msg;
}

static void builder_error(CFG_Builder* b, AST_Node* node, const char* fmt, ...) {
	int line = 0;
	int column = 0;
	if (node) {
		line = node->loc.first_line;
		column = node->loc.first_column;
	}
	va_list args;
	va_start(args, fmt);
	int msg_len = vsnprintf(NULL, 0, fmt, args) + 1;
	va_end(args);
	char* msg = malloc((size_t)msg_len);
	if (!msg) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	va_start(args, fmt);
	vsnprintf(msg, (size_t)msg_len, fmt, args);
	va_end(args);
	analysis_add_error(b->analysis, b->filename, line, column, "%s", msg);
	free(msg);
}

static void cfg_graph_init(CFG_Graph* graph) {
	graph->blocks = NULL;
	graph->block_count = 0;
	graph->block_capacity = 0;
	graph->entry_id = -1;
	graph->exit_id = -1;
}

static void cfg_block_init(CFG_Block* block, int id) {
	block->id = id;
	block->next = -1;
	block->true_next = -1;
	block->false_next = -1;
	block->label = NULL;
	block->ir = NULL;
	block->is_circle = 0;
	block->is_break = 0;
}

static int cfg_graph_add_block(CFG_Graph* graph) {
	if (graph->block_count == graph->block_capacity) {
		int new_cap = graph->block_capacity ? graph->block_capacity * 2 : 16;
		CFG_Block* p = realloc(graph->blocks, (size_t)new_cap * sizeof(CFG_Block));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		graph->blocks = p;
		graph->block_capacity = new_cap;
	}
	int id = graph->block_count;
	cfg_block_init(&graph->blocks[id], id);
	graph->block_count++;
	return id;
}

static CFG_Block* cfg_graph_get_block(CFG_Graph* graph, int id) {
	if (id < 0 || id >= graph->block_count) return NULL;
	return &graph->blocks[id];
}

static void cfg_graph_free(CFG_Graph* graph) {
	if (!graph) return;
	for (int i = 0; i < graph->block_count; i++) {
		free(graph->blocks[i].label);
		ir_free(graph->blocks[i].ir);
	}
	free(graph->blocks);
	graph->blocks = NULL;
	graph->block_count = 0;
	graph->block_capacity = 0;
	graph->entry_id = -1;
	graph->exit_id = -1;
}

static void connect_exits_to(CFG_Builder* b, CFG_ExitList* exits, int target) {
	for (int i = 0; i < exits->count; i++) {
		CFG_Block* block = cfg_graph_get_block(b->graph, exits->ids[i]);
		if (!block) continue;
		if (block->next != -1 || block->true_next != -1 || block->false_next != -1) continue;
		block->next = target;
	}
}

static const AST_Node* func_signature_node(const AST_Node* func_def) {
	if (!func_def || func_def->type != AST_FUNC_DEF || func_def->compound.child_count < 1) return NULL;
	return func_def->compound.children[0];
}

static AST_Node* func_body_list(AST_Node* func_def) {
	if (!func_def || func_def->type != AST_FUNC_DEF || func_def->compound.child_count < 2) return NULL;
	return func_def->compound.children[1];
}

static char* ast_type_to_string(AST_Node* node);

static char* ast_signature_name(AST_Node* signature) {
	if (!signature || signature->type != AST_FUNC_SIGNATURE || signature->compound.child_count < 1) {
		return xstrdup("");
	}
	AST_Node* name_node = signature->compound.children[0];
	if (!name_node || name_node->type != AST_ID || !name_node->id) {
		return expr_to_string(name_node);
	}
	return xstrdup(name_node->id);
}

static char* ast_signature_return_type(AST_Node* signature) {
	if (!signature || signature->type != AST_FUNC_SIGNATURE) return xstrdup("");
	if (signature->compound.child_count == 2 && signature->compound.children[1] && signature->compound.children[1]->type != AST_LIST) {
		return ast_type_to_string(signature->compound.children[1]);
	}
	if (signature->compound.child_count >= 3) {
		return ast_type_to_string(signature->compound.children[2]);
	}
	return xstrdup("");
}

static AST_Node* ast_signature_args_list(AST_Node* signature) {
	if (!signature || signature->type != AST_FUNC_SIGNATURE) return NULL;
	if (signature->compound.child_count >= 2 && signature->compound.children[1] && signature->compound.children[1]->type == AST_LIST) {
		return signature->compound.children[1];
	}
	return NULL;
}

static char* ast_type_to_string(AST_Node* node) {
	if (!node) return xstrdup("");
	if (node->type == AST_TYPE_REF && node->compound.child_count >= 1) {
		return ast_type_to_string(node->compound.children[0]);
	}
	if (node->type == AST_TYPE_ARRAY && node->compound.child_count >= 2) {
		char* base = ast_type_to_string(node->compound.children[0]);
		char* dim = expr_to_string(node->compound.children[1]);
		int len = snprintf(NULL, 0, "%s array[%s]", base, dim) + 1;
		char* res = malloc((size_t)len);
		if (!res) {
			perror("malloc");
			exit(EXIT_FAILURE);
		}
		snprintf(res, (size_t)len, "%s array[%s]", base, dim);
		free(base);
		free(dim);
		return res;
	}
	return expr_to_string(node);
}

static int type_is_array_name(const char* type_name) {
	return type_name && strstr(type_name, "array[") != NULL;
}

static int ast_type_size(AST_Node* node) {
	char* type_name = ast_type_to_string(node);
	int size = 4;
	if (type_is_array_name(type_name)) {
		const char* p = strstr(type_name, "array[");
		int dim = p ? atoi(p + 6) : 1;
		if (dim <= 0) dim = 1;
		size = dim * 4;
	}
	else if (strcmp(type_name, "bool") == 0 || strcmp(type_name, "byte") == 0 || strcmp(type_name, "char") == 0) {
		size = 1;
	}
	else {
		size = 4;
	}
	free(type_name);
	return size;
}

static void ast_signature_params(AST_Node* signature, CFG_Param** out_params, int* out_count) {
	*out_params = NULL;
	*out_count = 0;
	AST_Node* args_list = ast_signature_args_list(signature);
	if (!args_list) return;

	int count = args_list->compound.child_count;
	CFG_Param* params = calloc((size_t)count, sizeof(CFG_Param));
	if (!params) {
		perror("calloc");
		exit(EXIT_FAILURE);
	}
	int out_idx = 0;
	for (int i = 0; i < count; i++) {
		AST_Node* arg = args_list->compound.children[i];
		if (!arg || arg->type != AST_ARG_DEF || arg->compound.child_count < 1) continue;
		AST_Node* id_node = arg->compound.children[0];
		if (!id_node || id_node->type != AST_ID || !id_node->id) continue;
		AST_Node* type_ref = (arg->compound.child_count >= 2) ? arg->compound.children[1] : NULL;
		params[out_idx].name = xstrdup(id_node->id);
		params[out_idx].type = type_ref ? ast_type_to_string(type_ref) : xstrdup("");
		params[out_idx].size = type_ref ? ast_type_size(type_ref) : 4;
		out_idx++;
	}
	*out_params = params;
	*out_count = out_idx;
}

static char* ast_signature_to_string(AST_Node* signature, const char* owner_type) {
	char* name = ast_signature_name(signature);
	CFG_Param* params = NULL;
	int param_count = 0;
	ast_signature_params(signature, &params, &param_count);
	char* ret = ast_signature_return_type(signature);

	int total = 1;
	if (owner_type && owner_type[0] != '\0') total += (int)strlen(owner_type) + 1;
	total += (int)strlen(name) + 2;
	for (int i = 0; i < param_count; i++) {
		total += (int)strlen(params[i].name) + (params[i].type ? (int)strlen(params[i].type) + 4 : 0);
		if (i + 1 < param_count) total += 2;
	}
	if (ret && ret[0] != '\0') total += (int)strlen(ret) + 4;

	char* out = malloc((size_t)total);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	out[0] = '\0';
	if (owner_type && owner_type[0] != '\0') {
		strcat(out, owner_type);
		strcat(out, ".");
	}
	strcat(out, name);
	strcat(out, "(");
	for (int i = 0; i < param_count; i++) {
		strcat(out, params[i].name);
		if (params[i].type && params[i].type[0] != '\0') {
			strcat(out, " of ");
			strcat(out, params[i].type);
		}
		if (i + 1 < param_count) strcat(out, ", ");
	}
	strcat(out, ")");
	if (ret && ret[0] != '\0') {
		strcat(out, " of ");
		strcat(out, ret);
	}

	free(name);
	free(ret);
	for (int i = 0; i < param_count; i++) {
		free(params[i].name);
		free(params[i].type);
	}
	free(params);
	return out;
}

static AST_Node* type_name_node(AST_Node* node) {
	return (node && node->compound.child_count >= 1) ? node->compound.children[0] : NULL;
}

static int is_identifier_list(AST_Node* node) {
	if (!node || node->type != AST_LIST) return 0;
	for (int i = 0; i < node->compound.child_count; i++) {
		if (!node->compound.children[i] || node->compound.children[i]->type != AST_ID) return 0;
	}
	return 1;
}

static AST_Node* type_base_node(AST_Node* node) {
	if (!node || node->type != AST_TYPE_DEF || node->compound.child_count < 2) return NULL;
	int idx = 1;
	if (node->compound.children[idx] && node->compound.children[idx]->type == AST_ID) {
		return node->compound.children[idx];
	}
	return NULL;
}

static AST_Node* type_interfaces_node(AST_Node* node) {
	if (!node || node->type != AST_TYPE_DEF || node->compound.child_count < 2) return NULL;
	int idx = 1;
	if (idx < node->compound.child_count && node->compound.children[idx] && node->compound.children[idx]->type == AST_ID) {
		idx++;
	}
	if (idx < node->compound.child_count && is_identifier_list(node->compound.children[idx])) {
		return node->compound.children[idx];
	}
	return NULL;
}

static AST_Node* type_members_node(AST_Node* node) {
	if (!node || node->type != AST_TYPE_DEF || node->compound.child_count < 2) return NULL;
	for (int i = node->compound.child_count - 1; i >= 1; i--) {
		AST_Node* child = node->compound.children[i];
		if (child && child->type == AST_LIST && !is_identifier_list(child)) {
			return child;
		}
	}
	return NULL;
}

static AST_Node* interface_members_node(AST_Node* node) {
	if (!node || node->type != AST_INTERFACE_DEF || node->compound.child_count < 2) return NULL;
	return node->compound.children[1];
}

static int analysis_find_type_index(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return -1;
	for (int i = 0; i < analysis->type_count; i++) {
		if (analysis->types[i].name && strcmp(analysis->types[i].name, name) == 0) return i;
	}
	return -1;
}

static CFG_UserType* analysis_find_type_mut(CFG_Analysis* analysis, const char* name) {
	int idx = analysis_find_type_index(analysis, name);
	return idx >= 0 ? &analysis->types[idx] : NULL;
}

static const CFG_UserType* analysis_find_type_const(const CFG_Analysis* analysis, const char* name) {
	int idx = analysis_find_type_index(analysis, name);
	return idx >= 0 ? &analysis->types[idx] : NULL;
}

static void analysis_add_type(CFG_Analysis* analysis, const CFG_UserType* type) {
	if (analysis->type_count == analysis->type_capacity) {
		int new_cap = analysis->type_capacity ? analysis->type_capacity * 2 : 8;
		CFG_UserType* p = realloc(analysis->types, (size_t)new_cap * sizeof(CFG_UserType));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		analysis->types = p;
		analysis->type_capacity = new_cap;
	}
	analysis->types[analysis->type_count++] = *type;
}

static void user_type_add_interface(CFG_UserType* type, const char* name) {
	type->interface_names = realloc(type->interface_names, (size_t)(type->interface_count + 1) * sizeof(char*));
	if (!type->interface_names) {
		perror("realloc");
		exit(EXIT_FAILURE);
	}
	type->interface_names[type->interface_count++] = xstrdup(name);
}

static void user_type_add_field(CFG_UserType* type, const CFG_Field* field) {
	if (type->field_count == type->field_capacity) {
		int new_cap = type->field_capacity ? type->field_capacity * 2 : 8;
		CFG_Field* p = realloc(type->fields, (size_t)new_cap * sizeof(CFG_Field));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		type->fields = p;
		type->field_capacity = new_cap;
	}
	type->fields[type->field_count++] = *field;
}

static void user_type_add_method(CFG_UserType* type, const CFG_Method* method) {
	if (type->method_count == type->method_capacity) {
		int new_cap = type->method_capacity ? type->method_capacity * 2 : 8;
		CFG_Method* p = realloc(type->methods, (size_t)new_cap * sizeof(CFG_Method));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		type->methods = p;
		type->method_capacity = new_cap;
	}
	type->methods[type->method_count++] = *method;
}

static int user_type_find_field_index(const CFG_UserType* type, const char* name) {
	if (!type || !name) return -1;
	for (int i = 0; i < type->field_count; i++) {
		if (type->fields[i].name && strcmp(type->fields[i].name, name) == 0) return i;
	}
	return -1;
}

static int user_type_find_method_index(const CFG_UserType* type, const char* name) {
	if (!type || !name) return -1;
	for (int i = 0; i < type->method_count; i++) {
		if (type->methods[i].name && strcmp(type->methods[i].name, name) == 0) return i;
	}
	return -1;
}

static CFG_Method method_copy(const CFG_Method* src) {
	CFG_Method m;
	memset(&m, 0, sizeof(m));
	m.name = xstrdup(src->name);
	m.mangled_name = xstrdup(src->mangled_name);
	m.owner_type = xstrdup(src->owner_type);
	m.return_type = xstrdup(src->return_type);
	m.param_count = src->param_count;
	m.is_override = src->is_override;
	m.is_abstract = src->is_abstract;
	if (src->param_count > 0) {
		m.params = calloc((size_t)src->param_count, sizeof(CFG_Param));
		if (!m.params) {
			perror("calloc");
			exit(EXIT_FAILURE);
		}
		for (int i = 0; i < src->param_count; i++) {
			m.params[i].name = xstrdup(src->params[i].name);
			m.params[i].type = xstrdup(src->params[i].type);
			m.params[i].size = src->params[i].size;
		}
	}
	return m;
}

static CFG_Field field_copy(const CFG_Field* src) {
	CFG_Field f;
	memset(&f, 0, sizeof(f));
	f.name = xstrdup(src->name);
	f.type = xstrdup(src->type);
	f.owner_type = xstrdup(src->owner_type);
	f.slot_index = src->slot_index;
	return f;
}

static void method_free(CFG_Method* method) {
	free(method->name);
	free(method->mangled_name);
	free(method->owner_type);
	free(method->return_type);
	for (int i = 0; i < method->param_count; i++) {
		free(method->params[i].name);
		free(method->params[i].type);
	}
	free(method->params);
	memset(method, 0, sizeof(*method));
}

static void field_free(CFG_Field* field) {
	free(field->name);
	free(field->type);
	free(field->owner_type);
	memset(field, 0, sizeof(*field));
}

static int type_is_assignable_to(const CFG_Analysis* analysis, const char* concrete_name, const char* target_name) {
	if (!concrete_name || !target_name) return 0;
	if (strcmp(concrete_name, target_name) == 0) return 1;
	const CFG_UserType* type = analysis_find_type_const(analysis, concrete_name);
	while (type) {
		if (type->base_name && strcmp(type->base_name, target_name) == 0) return 1;
		for (int i = 0; i < type->interface_count; i++) {
			if (strcmp(type->interface_names[i], target_name) == 0) return 1;
			if (type_is_assignable_to(analysis, type->interface_names[i], target_name)) return 1;
		}
		if (!type->base_name) break;
		type = analysis_find_type_const(analysis, type->base_name);
	}
	return 0;
}

static char* make_mangled_method_name(const char* owner_type, const char* method_name) {
	int len = snprintf(NULL, 0, "%s__%s", owner_type ? owner_type : "type", method_name ? method_name : "method") + 1;
	char* out = malloc((size_t)len);
	if (!out) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(out, (size_t)len, "%s__%s", owner_type ? owner_type : "type", method_name ? method_name : "method");
	return out;
}

static CFG_Method method_from_signature(AST_Node* signature, const char* owner_type, int is_override, int is_abstract) {
	CFG_Method method;
	memset(&method, 0, sizeof(method));
	method.name = ast_signature_name(signature);
	method.mangled_name = is_abstract ? NULL : make_mangled_method_name(owner_type, method.name);
	method.owner_type = xstrdup(owner_type);
	method.return_type = ast_signature_return_type(signature);
	ast_signature_params(signature, &method.params, &method.param_count);
	method.is_override = is_override;
	method.is_abstract = is_abstract;
	return method;
}

static int same_signature(const CFG_Method* a, const CFG_Method* b) {
	if (!a || !b) return 0;
	if (strcmp(a->name ? a->name : "", b->name ? b->name : "") != 0) return 0;
	if (strcmp(a->return_type ? a->return_type : "", b->return_type ? b->return_type : "") != 0) return 0;
	if (a->param_count != b->param_count) return 0;
	for (int i = 0; i < a->param_count; i++) {
		if (strcmp(a->params[i].type ? a->params[i].type : "", b->params[i].type ? b->params[i].type : "") != 0) return 0;
	}
	return 1;
}

static void collect_top_level_items(AST_Node* node, const char* filename, PendingTypeList* types, PendingSubprogramList* subprograms) {
	if (!node) return;
	if (node->type == AST_TYPE_DEF || node->type == AST_INTERFACE_DEF) {
		pending_type_add(types, filename, node);
		return;
	}
	if (node->type == AST_FUNC_DEF) {
		pending_subprogram_add(subprograms, filename, node, NULL, 0, 0);
		if (node->compound.child_count >= 2) {
			collect_top_level_items(node->compound.children[1], filename, types, subprograms);
		}
		return;
	}
	if (node->type == AST_LIST || node->type == AST_BLOCK) {
		for (int i = 0; i < node->compound.child_count; i++) {
			collect_top_level_items(node->compound.children[i], filename, types, subprograms);
		}
	}
}

static void collect_method_subprograms(AST_Node* type_node, const char* filename, PendingSubprogramList* subprograms) {
	AST_Node* name_node = type_name_node(type_node);
	const char* owner_type = (name_node && name_node->type == AST_ID) ? name_node->id : NULL;
	AST_Node* members = type_members_node(type_node);
	if (!owner_type || !members) return;
	for (int i = 0; i < members->compound.child_count; i++) {
		AST_Node* member = members->compound.children[i];
		if (!member || member->type != AST_FUNC_DEF) continue;
		pending_subprogram_add(subprograms, filename, member, owner_type, 1, member->op && strcmp(member->op, "override") == 0);
	}
}

static void initialize_type_placeholders(CFG_Analysis* analysis, const PendingTypeList* pending_types) {
	for (int i = 0; i < pending_types->count; i++) {
		AST_Node* node = pending_types->items[i].node;
		AST_Node* name_node = type_name_node(node);
		if (!name_node || name_node->type != AST_ID || !name_node->id) {
			analysis_add_error(analysis, pending_types->items[i].filename, node->loc.first_line, node->loc.first_column, "Malformed type definition");
			continue;
		}
		if (analysis_find_type_index(analysis, name_node->id) >= 0) {
			analysis_add_error(analysis, pending_types->items[i].filename, name_node->loc.first_line, name_node->loc.first_column, "Duplicate type or interface '%s'", name_node->id);
			continue;
		}
		CFG_UserType type;
		memset(&type, 0, sizeof(type));
		type.name = xstrdup(name_node->id);
		type.is_interface = (node->type == AST_INTERFACE_DEF);
		AST_Node* base_node = type_base_node(node);
		if (base_node && base_node->type == AST_ID && base_node->id) {
			type.base_name = xstrdup(base_node->id);
		}
		AST_Node* interfaces = type_interfaces_node(node);
		if (interfaces) {
			for (int j = 0; j < interfaces->compound.child_count; j++) {
				AST_Node* iface = interfaces->compound.children[j];
				if (iface && iface->type == AST_ID && iface->id) {
					user_type_add_interface(&type, iface->id);
				}
			}
		}
		type.type_id = 0;
		type.object_word_size = type.is_interface ? 0 : 1;
		analysis_add_type(analysis, &type);
	}
}

static void resolve_interface(CFG_Analysis* analysis, const PendingType* pending, int* states);
static void resolve_concrete_type(CFG_Analysis* analysis, const PendingType* pending, int* states);

static void resolve_type_dispatch(CFG_Analysis* analysis, const PendingTypeList* pending_types) {
	int* states = calloc((size_t)pending_types->count, sizeof(int));
	if (!states) {
		perror("calloc");
		exit(EXIT_FAILURE);
	}
	for (int i = 0; i < pending_types->count; i++) {
		AST_Node* node = pending_types->items[i].node;
		if (node->type == AST_INTERFACE_DEF) resolve_interface(analysis, &pending_types->items[i], states);
	}
	for (int i = 0; i < pending_types->count; i++) {
		AST_Node* node = pending_types->items[i].node;
		if (node->type == AST_TYPE_DEF) resolve_concrete_type(analysis, &pending_types->items[i], states);
	}
	free(states);
}

static int pending_type_index_by_name(const PendingTypeList* pending_types, const char* name) {
	for (int i = 0; i < pending_types->count; i++) {
		AST_Node* name_node = type_name_node(pending_types->items[i].node);
		if (name_node && name_node->type == AST_ID && name_node->id && strcmp(name_node->id, name) == 0) return i;
	}
	return -1;
}

static const PendingTypeList* g_pending_types = NULL;

static void resolve_interface(CFG_Analysis* analysis, const PendingType* pending, int* states) {
	AST_Node* name_node = type_name_node(pending->node);
	int idx = pending_type_index_by_name(g_pending_types, name_node->id);
	if (idx < 0) return;
	if (states[idx] == 2) return;
	if (states[idx] == 1) {
		analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Cyclic interface declaration for '%s'", name_node->id);
		return;
	}
	states[idx] = 1;
	CFG_UserType* type = analysis_find_type_mut(analysis, name_node->id);
	AST_Node* members = interface_members_node(pending->node);
	if (members) {
		for (int i = 0; i < members->compound.child_count; i++) {
			AST_Node* member = members->compound.children[i];
			if (!member || member->type != AST_FUNC_SIGNATURE) continue;
			CFG_Method method = method_from_signature(member, type->name, 0, 1);
			int existing = user_type_find_method_index(type, method.name);
			if (existing >= 0) {
				analysis_add_error(analysis, pending->filename, member->loc.first_line, member->loc.first_column, "Duplicate interface method '%s.%s'", type->name, method.name);
				method_free(&method);
				continue;
			}
			user_type_add_method(type, &method);
		}
	}
	states[idx] = 2;
}

static void inherit_from_base(CFG_UserType* dst, const CFG_UserType* base) {
	if (!base) return;
	for (int i = 0; i < base->field_count; i++) {
		CFG_Field field = field_copy(&base->fields[i]);
		user_type_add_field(dst, &field);
	}
	for (int i = 0; i < base->method_count; i++) {
		CFG_Method method = method_copy(&base->methods[i]);
		user_type_add_method(dst, &method);
	}
	dst->object_word_size = base->object_word_size;
}

static void resolve_concrete_type(CFG_Analysis* analysis, const PendingType* pending, int* states) {
	AST_Node* name_node = type_name_node(pending->node);
	int idx = pending_type_index_by_name(g_pending_types, name_node->id);
	if (idx < 0) return;
	if (states[idx] == 2) return;
	if (states[idx] == 1) {
		analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Cyclic type inheritance for '%s'", name_node->id);
		return;
	}
	states[idx] = 1;

	CFG_UserType* type = analysis_find_type_mut(analysis, name_node->id);
	if (type->base_name) {
		int base_pending_idx = pending_type_index_by_name(g_pending_types, type->base_name);
		if (base_pending_idx >= 0) {
			AST_Node* base_node = g_pending_types->items[base_pending_idx].node;
			if (base_node->type == AST_INTERFACE_DEF) {
				analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Type '%s' cannot extend interface '%s'", type->name, type->base_name);
			}
			else {
				resolve_concrete_type(analysis, &g_pending_types->items[base_pending_idx], states);
				const CFG_UserType* base = analysis_find_type_const(analysis, type->base_name);
				if (base) inherit_from_base(type, base);
			}
		}
		else {
			analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Unknown base type '%s'", type->base_name);
		}
	}

	AST_Node* members = type_members_node(pending->node);
	if (members) {
		for (int i = 0; i < members->compound.child_count; i++) {
			AST_Node* member = members->compound.children[i];
			if (!member) continue;
			if (member->type == AST_FIELD_DEF) {
				if (member->compound.child_count < 2) continue;
				AST_Node* field_name = member->compound.children[0];
				AST_Node* field_type = member->compound.children[1];
				if (!field_name || field_name->type != AST_ID || !field_name->id) continue;
				if (user_type_find_field_index(type, field_name->id) >= 0) {
					analysis_add_error(analysis, pending->filename, member->loc.first_line, member->loc.first_column, "Duplicate field '%s.%s'", type->name, field_name->id);
					continue;
				}
				CFG_Field field;
				memset(&field, 0, sizeof(field));
				field.name = xstrdup(field_name->id);
				field.type = ast_type_to_string(field_type);
				field.owner_type = xstrdup(type->name);
				field.slot_index = type->field_count + 1;
				user_type_add_field(type, &field);
				type->object_word_size = type->field_count + 1;
				continue;
			}
			if (member->type == AST_FUNC_DEF) {
				AST_Node* signature = (AST_Node*)func_signature_node(member);
				CFG_Method method = method_from_signature(signature, type->name, member->op && strcmp(member->op, "override") == 0, 0);
				int existing_idx = user_type_find_method_index(type, method.name);
				if (existing_idx >= 0) {
					CFG_Method* existing = &type->methods[existing_idx];
					if (!method.is_override && !existing->is_abstract) {
						analysis_add_error(analysis, pending->filename, member->loc.first_line, member->loc.first_column, "Method '%s.%s' hides inherited method; use override", type->name, method.name);
					}
					if (method.is_override && existing->is_abstract) {
						method.is_override = 0;
					}
					if (method.is_override && !same_signature(existing, &method)) {
						analysis_add_error(analysis, pending->filename, member->loc.first_line, member->loc.first_column, "Override signature mismatch for '%s.%s'", type->name, method.name);
					}
					method_free(existing);
					type->methods[existing_idx] = method;
				}
				else {
					if (method.is_override) {
						analysis_add_error(analysis, pending->filename, member->loc.first_line, member->loc.first_column, "Method '%s.%s' marked override but no base implementation exists", type->name, method.name);
						method.is_override = 0;
					}
					user_type_add_method(type, &method);
				}
			}
		}
	}

	for (int i = 0; i < type->interface_count; i++) {
		const char* iface_name = type->interface_names[i];
		int iface_pending_idx = pending_type_index_by_name(g_pending_types, iface_name);
		if (iface_pending_idx < 0) {
			analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Unknown interface '%s'", iface_name);
			continue;
		}
		resolve_interface(analysis, &g_pending_types->items[iface_pending_idx], states);
		const CFG_UserType* iface = analysis_find_type_const(analysis, iface_name);
		if (!iface || !iface->is_interface) {
			analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "'%s' is not an interface", iface_name);
			continue;
		}
		for (int m = 0; m < iface->method_count; m++) {
			int method_idx = user_type_find_method_index(type, iface->methods[m].name);
			if (method_idx < 0) {
				analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Type '%s' does not implement interface method '%s.%s'", type->name, iface->name, iface->methods[m].name);
			}
			else if (!same_signature(&type->methods[method_idx], &iface->methods[m])) {
				analysis_add_error(analysis, pending->filename, pending->node->loc.first_line, pending->node->loc.first_column, "Interface signature mismatch for '%s.%s'", type->name, iface->methods[m].name);
			}
		}
	}

	states[idx] = 2;
}

static void assign_type_ids(CFG_Analysis* analysis) {
	int next_id = 1;
	for (int i = 0; i < analysis->type_count; i++) {
		if (analysis->types[i].is_interface) continue;
		analysis->types[i].type_id = next_id++;
	}
}

static void dispatcher_add_case(CFG_DispatchEntry* dispatch, const char* runtime_type, const char* impl_name, int type_id) {
	if (dispatch->case_count == dispatch->case_capacity) {
		int new_cap = dispatch->case_capacity ? dispatch->case_capacity * 2 : 8;
		CFG_DispatchCase* p = realloc(dispatch->cases, (size_t)new_cap * sizeof(CFG_DispatchCase));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		dispatch->cases = p;
		dispatch->case_capacity = new_cap;
	}
	dispatch->cases[dispatch->case_count].runtime_type = xstrdup(runtime_type);
	dispatch->cases[dispatch->case_count].impl_name = xstrdup(impl_name);
	dispatch->cases[dispatch->case_count].type_id = type_id;
	dispatch->case_count++;
}

static int analysis_find_dispatcher_index(const CFG_Analysis* analysis, const char* owner_type, const char* method_name) {
	for (int i = 0; i < analysis->dispatcher_count; i++) {
		const CFG_DispatchEntry* d = &analysis->dispatchers[i];
		if (strcmp(d->owner_type ? d->owner_type : "", owner_type ? owner_type : "") == 0 &&
			strcmp(d->method_name ? d->method_name : "", method_name ? method_name : "") == 0) {
			return i;
		}
	}
	return -1;
}

static void analysis_add_dispatcher(CFG_Analysis* analysis, const CFG_DispatchEntry* dispatch) {
	if (analysis->dispatcher_count == analysis->dispatcher_capacity) {
		int new_cap = analysis->dispatcher_capacity ? analysis->dispatcher_capacity * 2 : 8;
		CFG_DispatchEntry* p = realloc(analysis->dispatchers, (size_t)new_cap * sizeof(CFG_DispatchEntry));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		analysis->dispatchers = p;
		analysis->dispatcher_capacity = new_cap;
	}
	analysis->dispatchers[analysis->dispatcher_count++] = *dispatch;
}

static void build_dispatchers(CFG_Analysis* analysis) {
	for (int i = 0; i < analysis->type_count; i++) {
		const CFG_UserType* owner = &analysis->types[i];
		for (int m = 0; m < owner->method_count; m++) {
			const CFG_Method* method = &owner->methods[m];
			if (analysis_find_dispatcher_index(analysis, owner->name, method->name) >= 0) continue;

			CFG_DispatchEntry dispatch;
			memset(&dispatch, 0, sizeof(dispatch));
			int name_len = snprintf(NULL, 0, "__dispatch_%s_%s", owner->name, method->name) + 1;
			dispatch.name = malloc((size_t)name_len);
			if (!dispatch.name) {
				perror("malloc");
				exit(EXIT_FAILURE);
			}
			snprintf(dispatch.name, (size_t)name_len, "__dispatch_%s_%s", owner->name, method->name);
			dispatch.owner_type = xstrdup(owner->name);
			dispatch.method_name = xstrdup(method->name);
			dispatch.return_type = xstrdup(method->return_type);
			dispatch.param_count = method->param_count;
			if (dispatch.param_count > 0) {
				dispatch.params = calloc((size_t)dispatch.param_count, sizeof(CFG_Param));
				if (!dispatch.params) {
					perror("calloc");
					exit(EXIT_FAILURE);
				}
				for (int p = 0; p < dispatch.param_count; p++) {
					dispatch.params[p].name = xstrdup(method->params[p].name);
					dispatch.params[p].type = xstrdup(method->params[p].type);
					dispatch.params[p].size = method->params[p].size;
				}
			}

			for (int t = 0; t < analysis->type_count; t++) {
				const CFG_UserType* runtime = &analysis->types[t];
				if (runtime->is_interface) continue;
				if (!type_is_assignable_to(analysis, runtime->name, owner->name)) continue;
				int impl_idx = user_type_find_method_index(runtime, method->name);
				if (impl_idx < 0) continue;
				const CFG_Method* impl = &runtime->methods[impl_idx];
				if (impl->is_abstract || !impl->mangled_name) continue;
				dispatcher_add_case(&dispatch, runtime->name, impl->mangled_name, runtime->type_id);
			}

			analysis_add_dispatcher(analysis, &dispatch);
		}
	}
}

static int is_object_like_type_name(const CFG_Analysis* analysis, const char* type_name) {
	const CFG_UserType* type = analysis_find_type_const(analysis, type_name);
	return type != NULL && !type->is_interface;
}

static void subprogram_add_symbol(CFG_Subprogram* sp, const char* name, const char* type, int is_param, int is_auto_object) {
	for (int i = 0; i < sp->symbol_count; i++) {
		if (strcmp(sp->symbols[i].name, name) == 0) return;
	}
	if (sp->symbol_count == sp->symbol_capacity) {
		int new_cap = sp->symbol_capacity ? sp->symbol_capacity * 2 : 8;
		CFG_Symbol* p = realloc(sp->symbols, (size_t)new_cap * sizeof(CFG_Symbol));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		sp->symbols = p;
		sp->symbol_capacity = new_cap;
	}
	CFG_Symbol* sym = &sp->symbols[sp->symbol_count++];
	sym->name = xstrdup(name);
	sym->type = xstrdup(type);
	sym->is_param = is_param;
	sym->is_auto_object = is_auto_object;
}

static void collect_typed_locals(CFG_Subprogram* sp, const CFG_Analysis* analysis, AST_Node* node) {
	if (!node) return;
	switch (node->type) {
	case AST_ID:
	case AST_CHAR:
	case AST_STRING:
	case AST_NUM:
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL:
	case AST_TYPE_BOOL:
	case AST_TYPE_BYTE:
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	case AST_TYPE_CHAR:
	case AST_TYPE_STRING:
		return;
	default:
		break;
	}
	if (node->type == AST_FUNC_DEF || node->type == AST_TYPE_DEF || node->type == AST_INTERFACE_DEF) {
		return;
	}
	if (node->type == AST_VAR_DECL && node->compound.child_count >= 2) {
		AST_Node* id_node = node->compound.children[0];
		AST_Node* type_node = node->compound.children[1];
		if (id_node && id_node->type == AST_ID && id_node->id) {
			char* type_name = ast_type_to_string(type_node);
			int is_auto_object = is_object_like_type_name(analysis, type_name) && node->compound.child_count < 3;
			subprogram_add_symbol(sp, id_node->id, type_name, 0, is_auto_object);
			free(type_name);
		}
	}
	for (int i = 0; i < node->compound.child_count; i++) {
		collect_typed_locals(sp, analysis, node->compound.children[i]);
	}
}

static CFG_Fragment build_stmt(CFG_Builder* b, AST_Node* stmt, int break_target);

static CFG_Fragment build_stmt_list(CFG_Builder* b, AST_Node* stmt_list, int break_target) {
	CFG_Fragment result = fragment_empty();
	if (!stmt_list) return result;
	if (stmt_list->type != AST_LIST) {
		builder_error(b, stmt_list, "Expected AST_LIST for statements");
		return result;
	}
	for (int i = 0; i < stmt_list->compound.child_count; i++) {
		CFG_Fragment part = build_stmt(b, stmt_list->compound.children[i], break_target);
		if (part.entry == -1) {
			exit_list_free(&part.exits);
			continue;
		}
		if (result.entry == -1) {
			result.entry = part.entry;
			exit_list_move(&result.exits, &part.exits);
			exit_list_free(&part.exits);
			continue;
		}
		connect_exits_to(b, &result.exits, part.entry);
		exit_list_free(&result.exits);
		exit_list_move(&result.exits, &part.exits);
		exit_list_free(&part.exits);
	}
	return result;
}

static CFG_Fragment build_if(CFG_Builder* b, AST_Node* stmt, int break_target) {
	CFG_Fragment frag = fragment_empty();
	if (!stmt || stmt->compound.child_count < 2) {
		builder_error(b, stmt, "Malformed IF node");
		return frag;
	}
	AST_Node* cond_expr = stmt->compound.children[0];
	AST_Node* then_stmt = stmt->compound.children[1];
	AST_Node* else_stmt = NULL;
	if (stmt->compound.child_count >= 3 && stmt->compound.children[2] && stmt->compound.children[2]->type == AST_ELSE) {
		AST_Node* else_node = stmt->compound.children[2];
		if (else_node->compound.child_count >= 1) else_stmt = else_node->compound.children[0];
	}
	int cond_id = cfg_graph_add_block(b->graph);
	CFG_Block* cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->label = expr_to_string(cond_expr);
	IR_BuildContext ctx = { b->analysis, b->subprogram };
	cond_block->ir = ir_from_expr_ctx(cond_expr, &ctx, NULL);

	CFG_Fragment then_frag = build_stmt(b, then_stmt, break_target);
	CFG_Fragment else_frag = else_stmt ? build_stmt(b, else_stmt, break_target) : fragment_empty();
	int join_id = cfg_graph_add_block(b->graph);
	cfg_graph_get_block(b->graph, join_id)->is_circle = 1;
	cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->true_next = (then_frag.entry != -1) ? then_frag.entry : join_id;
	cond_block->false_next = (else_frag.entry != -1) ? else_frag.entry : join_id;
	connect_exits_to(b, &then_frag.exits, join_id);
	connect_exits_to(b, &else_frag.exits, join_id);
	exit_list_free(&then_frag.exits);
	exit_list_free(&else_frag.exits);
	frag.entry = cond_id;
	exit_list_add(&frag.exits, join_id);
	return frag;
}

static CFG_Fragment build_while_until(CFG_Builder* b, AST_Node* stmt) {
	CFG_Fragment frag = fragment_empty();
	if (!stmt || stmt->compound.child_count < 1) {
		builder_error(b, stmt, "Malformed loop node");
		return frag;
	}
	int cond_id = cfg_graph_add_block(b->graph);
	int after_id = cfg_graph_add_block(b->graph);
	cfg_graph_get_block(b->graph, after_id)->is_circle = 1;
	AST_Node* cond_expr = stmt->compound.children[0];
	CFG_Block* cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->label = expr_to_string(cond_expr);
	IR_BuildContext ctx = { b->analysis, b->subprogram };
	cond_block->ir = ir_from_expr_ctx(cond_expr, &ctx, NULL);
	CFG_Fragment body_frag = fragment_empty();
	if (stmt->compound.child_count >= 2) {
		body_frag = build_stmt_list(b, stmt->compound.children[1], after_id);
	}
	int is_until = (stmt->type == AST_UNTIL);
	cond_block = cfg_graph_get_block(b->graph, cond_id);
	if (body_frag.entry != -1) {
		if (!is_until) {
			cond_block->true_next = body_frag.entry;
			cond_block->false_next = after_id;
		}
		else {
			cond_block->true_next = after_id;
			cond_block->false_next = body_frag.entry;
		}
		connect_exits_to(b, &body_frag.exits, cond_id);
	}
	else {
		if (!is_until) {
			cond_block->true_next = cond_id;
			cond_block->false_next = after_id;
		}
		else {
			cond_block->true_next = after_id;
			cond_block->false_next = cond_id;
		}
	}
	exit_list_free(&body_frag.exits);
	frag.entry = cond_id;
	exit_list_add(&frag.exits, after_id);
	return frag;
}

static CFG_Fragment build_repeat_loop(CFG_Builder* b, AST_Node* stmt) {
	CFG_Fragment frag = fragment_empty();
	if (!stmt || stmt->compound.child_count < 2) {
		builder_error(b, stmt, "Malformed repeat loop");
		return frag;
	}
	int after_id = cfg_graph_add_block(b->graph);
	int cond_id = cfg_graph_add_block(b->graph);
	cfg_graph_get_block(b->graph, after_id)->is_circle = 1;

	AST_Node* body_stmt = stmt->compound.children[0];
	AST_Node* cond_expr = stmt->compound.children[1];
	CFG_Block* cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->label = expr_to_string(cond_expr);
	IR_BuildContext ctx = { b->analysis, b->subprogram };
	cond_block->ir = ir_from_expr_ctx(cond_expr, &ctx, NULL);

	CFG_Fragment body_frag = build_stmt(b, body_stmt, after_id);
	int body_entry = body_frag.entry;
	CFG_ExitList exits;
	exit_list_init(&exits);
	if (body_entry == -1) {
		body_entry = cfg_graph_add_block(b->graph);
		cfg_graph_get_block(b->graph, body_entry)->is_circle = 1;
		exit_list_add(&exits, body_entry);
	}
	else {
		exit_list_move(&exits, &body_frag.exits);
		exit_list_free(&body_frag.exits);
	}
	connect_exits_to(b, &exits, cond_id);
	exit_list_free(&exits);
	int is_until = (stmt->type == AST_REPEAT_UNTIL);
	cond_block = cfg_graph_get_block(b->graph, cond_id);
	if (!is_until) {
		cond_block->true_next = body_entry;
		cond_block->false_next = after_id;
	}
	else {
		cond_block->true_next = after_id;
		cond_block->false_next = body_entry;
	}
	frag.entry = body_entry;
	exit_list_add(&frag.exits, after_id);
	return frag;
}

static CFG_Fragment build_block(CFG_Builder* b, AST_Node* stmt, int break_target) {
	if (!stmt || stmt->compound.child_count == 0) return fragment_empty();
	return build_stmt_list(b, stmt->compound.children[0], break_target);
}

static CFG_Fragment build_stmt(CFG_Builder* b, AST_Node* stmt, int break_target) {
	CFG_Fragment frag = fragment_empty();
	if (!stmt) return frag;
	switch (stmt->type) {
	case AST_FUNC_DEF:
	case AST_TYPE_DEF:
	case AST_INTERFACE_DEF:
		return frag;
	case AST_IF:
		return build_if(b, stmt, break_target);
	case AST_WHILE:
	case AST_UNTIL:
		return build_while_until(b, stmt);
	case AST_REPEAT_WHILE:
	case AST_REPEAT_UNTIL:
		return build_repeat_loop(b, stmt);
	case AST_BLOCK:
		return build_block(b, stmt, break_target);
	case AST_BREAK: {
		int id = cfg_graph_add_block(b->graph);
		CFG_Block* block = cfg_graph_get_block(b->graph, id);
		block->label = xstrdup("BREAK");
		block->is_break = 1;
		block->next = (break_target >= 0) ? break_target : b->func_exit_id;
		if (break_target < 0) {
			builder_error(b, stmt, "BREAK used outside loop");
		}
		frag.entry = id;
		return frag;
	}
	default: {
		int id = cfg_graph_add_block(b->graph);
		CFG_Block* block = cfg_graph_get_block(b->graph, id);
		block->label = expr_to_string(stmt);
		IR_BuildContext ctx = { b->analysis, b->subprogram };
		char* ir_error = NULL;
		block->ir = ir_from_statement_ctx(stmt, &ctx, &ir_error);
		if (ir_error) {
			builder_error(b, stmt, "%s", ir_error);
			free(ir_error);
		}
		frag.entry = id;
		exit_list_add(&frag.exits, id);
		return frag;
	}
	}
}

static CFG_Graph build_cfg_for_subprogram(CFG_Analysis* analysis, const char* filename, const CFG_Subprogram* sp, AST_Node* func_def) {
	CFG_Graph graph;
	cfg_graph_init(&graph);
	graph.entry_id = cfg_graph_add_block(&graph);
	graph.exit_id = cfg_graph_add_block(&graph);
	cfg_graph_get_block(&graph, graph.entry_id)->label = xstrdup(sp->name ? sp->name : "");
	cfg_graph_get_block(&graph, graph.exit_id)->label = xstrdup("RET");

	CFG_Builder builder;
	builder.graph = &graph;
	builder.analysis = analysis;
	builder.filename = filename;
	builder.subprogram = sp;
	builder.func_exit_id = graph.exit_id;

	CFG_Fragment body = fragment_empty();
	AST_Node* body_list = func_body_list(func_def);
	if (body_list) body = build_stmt_list(&builder, body_list, -1);

	CFG_Block* entry = cfg_graph_get_block(&graph, graph.entry_id);
	if (body.entry != -1) {
		entry->next = body.entry;
		connect_exits_to(&builder, &body.exits, graph.exit_id);
	}
	else {
		entry->next = graph.exit_id;
	}
	exit_list_free(&body.exits);
	return graph;
}

static void analysis_add_subprogram(CFG_Analysis* analysis, CFG_Subprogram* sp) {
	if (analysis->subprogram_count == analysis->subprogram_capacity) {
		int new_cap = analysis->subprogram_capacity ? analysis->subprogram_capacity * 2 : 16;
		CFG_Subprogram* p = realloc(analysis->subprograms, (size_t)new_cap * sizeof(CFG_Subprogram));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		analysis->subprograms = p;
		analysis->subprogram_capacity = new_cap;
	}
	analysis->subprograms[analysis->subprogram_count++] = *sp;
}

static CFG_Subprogram create_subprogram_from_pending(const CFG_Analysis* analysis, const PendingSubprogram* pending) {
	CFG_Subprogram sp;
	memset(&sp, 0, sizeof(sp));
	AST_Node* signature = (AST_Node*)func_signature_node(pending->func_def);
	char* base_name = ast_signature_name(signature);
	if (pending->is_method) {
		const CFG_UserType* owner = analysis_find_type_const(analysis, pending->owner_type);
		int method_idx = owner ? user_type_find_method_index(owner, base_name) : -1;
		const CFG_Method* method = (owner && method_idx >= 0) ? &owner->methods[method_idx] : NULL;
		sp.name = method && method->mangled_name ? xstrdup(method->mangled_name) : make_mangled_method_name(pending->owner_type, base_name);
		sp.method_name = xstrdup(base_name);
		sp.owner_type = xstrdup(pending->owner_type);
		sp.is_method = 1;
		sp.is_override = pending->is_override;
		sp.signature = ast_signature_to_string(signature, pending->owner_type);
		sp.return_type = method ? xstrdup(method->return_type) : ast_signature_return_type(signature);
		sp.param_count = (method ? method->param_count : 0) + 1;
		sp.params = calloc((size_t)sp.param_count, sizeof(CFG_Param));
		if (!sp.params) {
			perror("calloc");
			exit(EXIT_FAILURE);
		}
		sp.params[0].name = xstrdup("self");
		sp.params[0].type = xstrdup(pending->owner_type);
		sp.params[0].size = 4;
		if (method) {
			for (int i = 0; i < method->param_count; i++) {
				sp.params[i + 1].name = xstrdup(method->params[i].name);
				sp.params[i + 1].type = xstrdup(method->params[i].type);
				sp.params[i + 1].size = method->params[i].size;
			}
		}
	}
	else {
		sp.name = xstrdup(base_name);
		sp.signature = ast_signature_to_string(signature, NULL);
		sp.return_type = ast_signature_return_type(signature);
		ast_signature_params(signature, &sp.params, &sp.param_count);
	}
	sp.source_filename = xstrdup(pending->filename);
	for (int i = 0; i < sp.param_count; i++) {
		subprogram_add_symbol(&sp, sp.params[i].name, sp.params[i].type, 1, 0);
	}
	collect_typed_locals(&sp, analysis, func_body_list(pending->func_def));
	free(base_name);
	return sp;
}

static void build_all_subprograms(CFG_Analysis* analysis, const PendingSubprogramList* subprograms) {
	for (int i = 0; i < subprograms->count; i++) {
		CFG_Subprogram sp = create_subprogram_from_pending(analysis, &subprograms->items[i]);
		sp.cfg = build_cfg_for_subprogram(analysis, subprograms->items[i].filename, &sp, subprograms->items[i].func_def);
		analysis_add_subprogram(analysis, &sp);
	}
}

CFG_Analysis cfg_analyze_files(const CFG_InputFile* files, int file_count) {
	CFG_Analysis analysis;
	memset(&analysis, 0, sizeof(analysis));

	PendingTypeList pending_types;
	memset(&pending_types, 0, sizeof(pending_types));
	PendingSubprogramList pending_subprograms;
	memset(&pending_subprograms, 0, sizeof(pending_subprograms));

	for (int i = 0; i < file_count; i++) {
		if (!files[i].parse_tree) continue;
		collect_top_level_items(files[i].parse_tree, files[i].filename, &pending_types, &pending_subprograms);
	}
	for (int i = 0; i < pending_types.count; i++) {
		if (pending_types.items[i].node->type == AST_TYPE_DEF) {
			collect_method_subprograms(pending_types.items[i].node, pending_types.items[i].filename, &pending_subprograms);
		}
	}

	initialize_type_placeholders(&analysis, &pending_types);
	g_pending_types = &pending_types;
	resolve_type_dispatch(&analysis, &pending_types);
	assign_type_ids(&analysis);
	build_dispatchers(&analysis);
	build_all_subprograms(&analysis, &pending_subprograms);

	free(pending_types.items);
	pending_subprograms_free(&pending_subprograms);
	return analysis;
}

void cfg_free_analysis(CFG_Analysis* analysis) {
	if (!analysis) return;
	for (int i = 0; i < analysis->subprogram_count; i++) {
		CFG_Subprogram* sp = &analysis->subprograms[i];
		free(sp->name);
		free(sp->signature);
		free(sp->source_filename);
		free(sp->owner_type);
		free(sp->method_name);
		free(sp->return_type);
		for (int p = 0; p < sp->param_count; p++) {
			free(sp->params[p].name);
			free(sp->params[p].type);
		}
		free(sp->params);
		for (int s = 0; s < sp->symbol_count; s++) {
			free(sp->symbols[s].name);
			free(sp->symbols[s].type);
		}
		free(sp->symbols);
		cfg_graph_free(&sp->cfg);
	}
	free(analysis->subprograms);
	analysis->subprograms = NULL;
	analysis->subprogram_count = 0;
	analysis->subprogram_capacity = 0;

	for (int i = 0; i < analysis->type_count; i++) {
		CFG_UserType* type = &analysis->types[i];
		free(type->name);
		free(type->base_name);
		for (int j = 0; j < type->interface_count; j++) {
			free(type->interface_names[j]);
		}
		free(type->interface_names);
		for (int f = 0; f < type->field_count; f++) {
			field_free(&type->fields[f]);
		}
		free(type->fields);
		for (int m = 0; m < type->method_count; m++) {
			method_free(&type->methods[m]);
		}
		free(type->methods);
	}
	free(analysis->types);
	analysis->types = NULL;
	analysis->type_count = 0;
	analysis->type_capacity = 0;

	for (int i = 0; i < analysis->dispatcher_count; i++) {
		CFG_DispatchEntry* d = &analysis->dispatchers[i];
		free(d->name);
		free(d->owner_type);
		free(d->method_name);
		free(d->return_type);
		for (int p = 0; p < d->param_count; p++) {
			free(d->params[p].name);
			free(d->params[p].type);
		}
		free(d->params);
		for (int c = 0; c < d->case_count; c++) {
			free(d->cases[c].runtime_type);
			free(d->cases[c].impl_name);
		}
		free(d->cases);
	}
	free(analysis->dispatchers);
	analysis->dispatchers = NULL;
	analysis->dispatcher_count = 0;
	analysis->dispatcher_capacity = 0;

	for (int i = 0; i < analysis->error_count; i++) {
		free(analysis->errors[i].filename);
		free(analysis->errors[i].message);
	}
	free(analysis->errors);
	analysis->errors = NULL;
	analysis->error_count = 0;
	analysis->error_capacity = 0;
}

static int callgraph_find_node(const CallGraph* g, const char* name) {
	for (int i = 0; i < g->node_count; i++) {
		if (strcmp(g->node_names[i], name) == 0) return i;
	}
	return -1;
}

static int callgraph_add_node(CallGraph* g, const char* name) {
	int idx = callgraph_find_node(g, name);
	if (idx >= 0) return idx;
	if (g->node_count == g->node_capacity) {
		int new_cap = g->node_capacity ? g->node_capacity * 2 : 16;
		char** p = realloc(g->node_names, (size_t)new_cap * sizeof(char*));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		g->node_names = p;
		g->node_capacity = new_cap;
	}
	g->node_names[g->node_count] = xstrdup(name);
	return g->node_count++;
}

static int callgraph_has_edge(const CallGraph* g, int from, int to) {
	for (int i = 0; i < g->edge_count; i++) {
		if (g->edges[i].from == from && g->edges[i].to == to) return 1;
	}
	return 0;
}

static void callgraph_add_edge(CallGraph* g, int from, int to) {
	if (from < 0 || to < 0 || callgraph_has_edge(g, from, to)) return;
	if (g->edge_count == g->edge_capacity) {
		int new_cap = g->edge_capacity ? g->edge_capacity * 2 : 32;
		CallGraph_Edge* p = realloc(g->edges, (size_t)new_cap * sizeof(CallGraph_Edge));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		g->edges = p;
		g->edge_capacity = new_cap;
	}
	g->edges[g->edge_count].from = from;
	g->edges[g->edge_count].to = to;
	g->edge_count++;
}

static void collect_calls_in_ir(CallGraph* cg, int from_idx, const IRNode* node) {
	if (!node) return;
	if ((node->type == IR_NODE_CALL || node->type == IR_NODE_METHOD_CALL) && node->text) {
		int to_idx = callgraph_add_node(cg, node->text);
		callgraph_add_edge(cg, from_idx, to_idx);
	}
	for (int i = 0; i < node->child_count; i++) {
		collect_calls_in_ir(cg, from_idx, node->children[i]);
	}
}

CallGraph cfg_build_call_graph(const CFG_Analysis* analysis) {
	CallGraph cg;
	memset(&cg, 0, sizeof(cg));
	for (int i = 0; i < analysis->subprogram_count; i++) {
		callgraph_add_node(&cg, analysis->subprograms[i].name);
	}
	for (int i = 0; i < analysis->dispatcher_count; i++) {
		callgraph_add_node(&cg, analysis->dispatchers[i].name);
	}
	for (int i = 0; i < analysis->subprogram_count; i++) {
		const CFG_Subprogram* sp = &analysis->subprograms[i];
		int from = callgraph_add_node(&cg, sp->name);
		for (int b = 0; b < sp->cfg.block_count; b++) {
			collect_calls_in_ir(&cg, from, sp->cfg.blocks[b].ir);
		}
	}
	return cg;
}

void cfg_free_call_graph(CallGraph* graph) {
	if (!graph) return;
	for (int i = 0; i < graph->node_count; i++) {
		free(graph->node_names[i]);
	}
	free(graph->node_names);
	free(graph->edges);
	memset(graph, 0, sizeof(*graph));
}
