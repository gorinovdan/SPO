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
	int func_exit_id;
} CFG_Builder;

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
		int* p = realloc(list->ids, new_cap * sizeof(int));
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

static void analysis_add_error(CFG_Analysis* analysis, const char* filename, int line, int column, const char* fmt, ...) {
	if (analysis->error_count == analysis->error_capacity) {
		int new_cap = analysis->error_capacity ? analysis->error_capacity * 2 : 16;
		CFG_Error* p = realloc(analysis->errors, new_cap * sizeof(CFG_Error));
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

	char* msg = malloc(msg_len);
	if (!msg) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	va_start(args, fmt);
	vsnprintf(msg, msg_len, fmt, args);
	va_end(args);

	CFG_Error* err = &analysis->errors[analysis->error_count++];
	err->filename = filename ? strdup(filename) : NULL;
	err->line = line;
	err->column = column;
	err->message = msg;
}

static void builder_error(CFG_Builder* b, AST_Node* node, const char* fmt, ...) {
	int line = 0;
	int col = 0;
	if (node) {
		line = node->loc.first_line;
		col = node->loc.first_column;
	}

	va_list args;
	va_start(args, fmt);
	int msg_len = vsnprintf(NULL, 0, fmt, args) + 1;
	va_end(args);

	char* msg = malloc(msg_len);
	if (!msg) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}

	va_start(args, fmt);
	vsnprintf(msg, msg_len, fmt, args);
	va_end(args);

	analysis_add_error(b->analysis, b->filename, line, col, "%s", msg);
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
		CFG_Block* p = realloc(graph->blocks, new_cap * sizeof(CFG_Block));
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
		graph->blocks[i].label = NULL;
		ir_free(graph->blocks[i].ir);
		graph->blocks[i].ir = NULL;
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
		if (block->next != -1 || block->true_next != -1 || block->false_next != -1) {
			/* should not happen for fallthrough exits */
			continue;
		}
		block->next = target;
	}
}

static CFG_Fragment build_stmt(CFG_Builder* b, AST_Node* stmt, int break_target);

static CFG_Fragment build_stmt_list(CFG_Builder* b, AST_Node* stmt_list, int break_target) {
	CFG_Fragment result = fragment_empty();
	if (!stmt_list) return result;
	if (stmt_list->type != AST_LIST) {
		builder_error(b, stmt_list, "Expected statement list (AST_LIST)");
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
		if (else_node->compound.child_count >= 1) {
			else_stmt = else_node->compound.children[0];
		}
	}

	int cond_id = cfg_graph_add_block(b->graph);
	CFG_Block* cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->label = expr_to_string(cond_expr);
	cond_block->ir = ir_from_expr(cond_expr);

	CFG_Fragment then_frag = build_stmt(b, then_stmt, break_target);
	CFG_Fragment else_frag = else_stmt ? build_stmt(b, else_stmt, break_target) : fragment_empty();

	int join_id = cfg_graph_add_block(b->graph);
	cfg_graph_get_block(b->graph, join_id)->is_circle = 1;

	/* `cfg_graph_add_block` may realloc `graph->blocks` and invalidate pointers */
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
	cond_block->ir = ir_from_expr(cond_expr);

	int has_body = (stmt->compound.child_count >= 2);
	CFG_Fragment body_frag = fragment_empty();
	if (has_body) {
		AST_Node* body_list = stmt->compound.children[1];
		body_frag = build_stmt_list(b, body_list, after_id);
	}

	int is_until = (stmt->type == AST_UNTIL);

	/* `build_stmt_list` may add blocks and realloc `graph->blocks` */
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
		/* empty body */
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
		builder_error(b, stmt, "Malformed repeat-loop node");
		return frag;
	}

	int after_id = cfg_graph_add_block(b->graph);
	int cond_id = cfg_graph_add_block(b->graph);
	cfg_graph_get_block(b->graph, after_id)->is_circle = 1;

	AST_Node* body_stmt = stmt->compound.children[0];
	AST_Node* cond_expr = stmt->compound.children[1];

	CFG_Block* cond_block = cfg_graph_get_block(b->graph, cond_id);
	cond_block->label = expr_to_string(cond_expr);
	cond_block->ir = ir_from_expr(cond_expr);

	CFG_Fragment body_frag = build_stmt(b, body_stmt, after_id);

	int body_entry = body_frag.entry;
	CFG_ExitList body_exits;
	exit_list_init(&body_exits);

	if (body_entry == -1) {
		body_entry = cfg_graph_add_block(b->graph);
		cfg_graph_get_block(b->graph, body_entry)->is_circle = 1;
		exit_list_add(&body_exits, body_entry);
	}
	else {
		exit_list_move(&body_exits, &body_frag.exits);
		exit_list_free(&body_frag.exits);
	}

	connect_exits_to(b, &body_exits, cond_id);
	exit_list_free(&body_exits);

	int is_until = (stmt->type == AST_REPEAT_UNTIL);

	/* `build_stmt` may add blocks and realloc `graph->blocks` */
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
	CFG_Fragment frag = fragment_empty();
	if (!stmt) return frag;
	if (stmt->compound.child_count == 0) return frag;

	AST_Node* items = stmt->compound.children[0];
	return build_stmt_list(b, items, break_target);
}

static CFG_Fragment build_stmt(CFG_Builder* b, AST_Node* stmt, int break_target) {
	CFG_Fragment frag = fragment_empty();
	if (!stmt) return frag;

	switch (stmt->type) {
	case AST_FUNC_DEF:
		/* nested function definition is not an executable statement */
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
		block->label = strdup("BREAK");
		block->is_break = 1;
		if (break_target >= 0) {
			block->next = break_target;
		}
		else {
			builder_error(b, stmt, "BREAK used outside of a loop");
			block->next = b->func_exit_id;
		}
		frag.entry = id;
		return frag;
	}
	default: {
		int id = cfg_graph_add_block(b->graph);
		CFG_Block* block = cfg_graph_get_block(b->graph, id);
		block->label = expr_to_string(stmt);
		char* ir_error_msg = NULL;
		block->ir = ir_from_statement(stmt, &ir_error_msg);
		if (ir_error_msg) {
			builder_error(b, stmt, "%s", ir_error_msg);
			free(ir_error_msg);
		}
		frag.entry = id;
		exit_list_add(&frag.exits, id);
		return frag;
	}
	}
}

static char* ast_type_to_string(AST_Node* node);

static char* ast_arg_def_to_string(AST_Node* node) {
	if (!node || node->type != AST_ARG_DEF || node->compound.child_count < 1) {
		return strdup("");
	}

	AST_Node* id_node = node->compound.children[0];
	char* name = expr_to_string(id_node);

	if (node->compound.child_count < 2) {
		return name;
	}

	AST_Node* type_ref = node->compound.children[1];
	char* type_str = ast_type_to_string(type_ref);

	int len = snprintf(NULL, 0, "%s of %s", name, type_str) + 1;
	char* res = malloc(len);
	snprintf(res, len, "%s of %s", name, type_str);

	free(name);
	free(type_str);
	return res;
}

static char* ast_type_to_string(AST_Node* node) {
	if (!node) return strdup("");
	if (node->type == AST_TYPE_REF && node->compound.child_count >= 1) {
		return ast_type_to_string(node->compound.children[0]);
	}
	if (node->type == AST_TYPE_ARRAY && node->compound.child_count >= 2) {
		char* base = ast_type_to_string(node->compound.children[0]);
		char* dim = expr_to_string(node->compound.children[1]);
		int len = snprintf(NULL, 0, "%s array[%s]", base, dim) + 1;
		char* res = malloc(len);
		snprintf(res, len, "%s array[%s]", base, dim);
		free(base);
		free(dim);
		return res;
	}
	/* builtin types and identifiers */
	return expr_to_string(node);
}

static int ast_type_size(AST_Node* node) {
	if (!node) return 4;
	if (node->type == AST_TYPE_REF && node->compound.child_count >= 1) {
		return ast_type_size(node->compound.children[0]);
	}
	if (node->type == AST_TYPE_ARRAY && node->compound.child_count >= 2) {
		int base = ast_type_size(node->compound.children[0]);
		AST_Node* dim_node = node->compound.children[1];
		int dim = 1;
		if (dim_node && (dim_node->type == AST_NUM || dim_node->type == AST_HEX || dim_node->type == AST_BIT)) {
			if (dim_node->num_str) {
				dim = (int)strtol(dim_node->num_str, NULL, 0);
			}
			else {
				dim = (int)dim_node->num_val;
			}
		}
		if (dim <= 0) dim = 1;
		if (base < 4) base = 4;
		return base * dim;
	}

	switch (node->type) {
	case AST_TYPE_BOOL:
	case AST_TYPE_BYTE:
	case AST_TYPE_CHAR:
		return 1;
	case AST_TYPE_STRING:
		return 4;
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	default:
		return 4;
	}
}

static char* ast_signature_to_string(AST_Node* signature) {
	if (!signature || signature->type != AST_FUNC_SIGNATURE || signature->compound.child_count < 1) {
		return strdup("");
	}

	AST_Node* name_node = signature->compound.children[0];
	char* name = expr_to_string(name_node);

	AST_Node* args_list = NULL;
	AST_Node* return_type = NULL;

	if (signature->compound.child_count == 2) {
		if (signature->compound.children[1]->type == AST_LIST) {
			args_list = signature->compound.children[1];
		}
		else {
			return_type = signature->compound.children[1];
		}
	}
	else if (signature->compound.child_count >= 3) {
		args_list = signature->compound.children[1];
		return_type = signature->compound.children[2];
	}

	char* args_str = strdup("");
	if (args_list && args_list->type == AST_LIST) {
		char** parts = malloc(args_list->compound.child_count * sizeof(char*));
		for (int i = 0; i < args_list->compound.child_count; i++) {
			parts[i] = ast_arg_def_to_string(args_list->compound.children[i]);
		}

		/* join */
		int total = 1;
		for (int i = 0; i < args_list->compound.child_count; i++) total += (int)strlen(parts[i]);
		total += (args_list->compound.child_count > 0 ? (args_list->compound.child_count - 1) * 2 : 0);
		free(args_str);
		args_str = malloc(total);
		args_str[0] = '\0';
		for (int i = 0; i < args_list->compound.child_count; i++) {
			strcat(args_str, parts[i]);
			if (i + 1 < args_list->compound.child_count) strcat(args_str, ", ");
			free(parts[i]);
		}
		free(parts);
	}

	char* type_str = NULL;
	if (return_type) type_str = ast_type_to_string(return_type);

	char* res;
	if (type_str && type_str[0] != '\0') {
		int len = snprintf(NULL, 0, "%s(%s) of %s", name, args_str, type_str) + 1;
		res = malloc(len);
		snprintf(res, len, "%s(%s) of %s", name, args_str, type_str);
	}
	else {
		int len = snprintf(NULL, 0, "%s(%s)", name, args_str) + 1;
		res = malloc(len);
		snprintf(res, len, "%s(%s)", name, args_str);
	}

	free(name);
	free(args_str);
	free(type_str);
	return res;
}

static void ast_signature_params(AST_Node* signature, CFG_Param** out_params, int* out_count) {
	*out_params = NULL;
	*out_count = 0;
	if (!signature || signature->type != AST_FUNC_SIGNATURE || signature->compound.child_count < 1) {
		return;
	}

	AST_Node* args_list = NULL;
	if (signature->compound.child_count >= 2 && signature->compound.children[1] && signature->compound.children[1]->type == AST_LIST) {
		args_list = signature->compound.children[1];
	}

	if (!args_list) return;

	int count = args_list->compound.child_count;
	if (count <= 0) return;

	CFG_Param* params = calloc(count, sizeof(CFG_Param));
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

		params[out_idx].name = strdup(id_node->id);
		params[out_idx].type = type_ref ? ast_type_to_string(type_ref) : strdup("");
		params[out_idx].size = type_ref ? ast_type_size(type_ref) : 4;
		out_idx++;
	}

	*out_params = params;
	*out_count = out_idx;
}

static char* ast_signature_name(AST_Node* signature) {
	if (!signature || signature->type != AST_FUNC_SIGNATURE || signature->compound.child_count < 1) {
		return strdup("");
	}
	AST_Node* name_node = signature->compound.children[0];
	if (!name_node || name_node->type != AST_ID) {
		return expr_to_string(name_node);
	}
	return strdup(name_node->id);
}

static CFG_Graph build_cfg_for_func(CFG_Analysis* analysis, const char* filename, const char* func_name, AST_Node* func_def) {
	CFG_Graph graph;
	cfg_graph_init(&graph);

	graph.entry_id = cfg_graph_add_block(&graph);
	graph.exit_id = cfg_graph_add_block(&graph);

	CFG_Block* entry_block = cfg_graph_get_block(&graph, graph.entry_id);
	entry_block->label = func_name ? strdup(func_name) : strdup("");
	CFG_Block* exit_block = cfg_graph_get_block(&graph, graph.exit_id);
	exit_block->label = strdup("RET");

	CFG_Builder builder;
	builder.graph = &graph;
	builder.analysis = analysis;
	builder.filename = filename;
	builder.func_exit_id = graph.exit_id;

	AST_Node* body_list = NULL;
	if (func_def && func_def->compound.child_count >= 2) {
		body_list = func_def->compound.children[1];
	}

	CFG_Fragment body = fragment_empty();
	if (body_list) {
		body = build_stmt_list(&builder, body_list, -1);
	}

	/* `build_stmt_list` may add blocks and realloc `graph.blocks` */
	entry_block = cfg_graph_get_block(&graph, graph.entry_id);
	if (body.entry != -1) {
		entry_block->next = body.entry;
		connect_exits_to(&builder, &body.exits, graph.exit_id);
	}
	else {
		entry_block->next = graph.exit_id;
	}

	exit_list_free(&body.exits);
	return graph;
}

static void analysis_add_subprogram(CFG_Analysis* analysis, CFG_Subprogram* sub) {
	if (analysis->subprogram_count == analysis->subprogram_capacity) {
		int new_cap = analysis->subprogram_capacity ? analysis->subprogram_capacity * 2 : 16;
		CFG_Subprogram* p = realloc(analysis->subprograms, new_cap * sizeof(CFG_Subprogram));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		analysis->subprograms = p;
		analysis->subprogram_capacity = new_cap;
	}
	analysis->subprograms[analysis->subprogram_count++] = *sub;
}

static void collect_functions_in_tree(CFG_Analysis* analysis, const char* filename, AST_Node* node) {
	if (!node) return;

	if (node->type == AST_FUNC_DEF) {
		if (node->compound.child_count < 1) {
			analysis_add_error(analysis, filename, node->loc.first_line, node->loc.first_column, "Malformed function definition");
		}
		else {
			AST_Node* signature = node->compound.children[0];
			char* name = ast_signature_name(signature);
			char* sig_str = ast_signature_to_string(signature);
			CFG_Param* params = NULL;
			int param_count = 0;
			ast_signature_params(signature, &params, &param_count);

			CFG_Subprogram sp;
			memset(&sp, 0, sizeof(CFG_Subprogram));
			sp.name = name;
			sp.signature = sig_str;
			sp.source_filename = filename ? strdup(filename) : NULL;
			sp.params = params;
			sp.param_count = param_count;
			sp.cfg = build_cfg_for_func(analysis, filename, name, node);

			analysis_add_subprogram(analysis, &sp);
		}
	}

	/* traverse children */
	switch (node->type) {
	case AST_CHAR:
	case AST_TYPE_ARRAY_DIMENTION:
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL:
	case AST_NUM:
	case AST_TYPE_STRING:
	case AST_TYPE_BOOL:
	case AST_TYPE_INT:
	case AST_TYPE_UINT:
	case AST_TYPE_LONG:
	case AST_TYPE_ULONG:
	case AST_TYPE_BYTE:
	case AST_TYPE_CHAR:
	case AST_ID:
	case AST_STRING:
		return;
	default:
		for (int i = 0; i < node->compound.child_count; i++) {
			collect_functions_in_tree(analysis, filename, node->compound.children[i]);
		}
		return;
	}
}

CFG_Analysis cfg_analyze_files(const CFG_InputFile* files, int file_count) {
	CFG_Analysis analysis;
	memset(&analysis, 0, sizeof(CFG_Analysis));

	for (int i = 0; i < file_count; i++) {
		if (!files[i].parse_tree) continue;
		collect_functions_in_tree(&analysis, files[i].filename, files[i].parse_tree);
	}

	return analysis;
}

void cfg_free_analysis(CFG_Analysis* analysis) {
	if (!analysis) return;

	for (int i = 0; i < analysis->subprogram_count; i++) {
		free(analysis->subprograms[i].name);
		free(analysis->subprograms[i].signature);
		free(analysis->subprograms[i].source_filename);
		for (int p = 0; p < analysis->subprograms[i].param_count; p++) {
			free(analysis->subprograms[i].params[p].name);
			free(analysis->subprograms[i].params[p].type);
		}
		free(analysis->subprograms[i].params);
		cfg_graph_free(&analysis->subprograms[i].cfg);
	}
	free(analysis->subprograms);
	analysis->subprograms = NULL;
	analysis->subprogram_count = 0;
	analysis->subprogram_capacity = 0;

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
		char** p = realloc(g->node_names, new_cap * sizeof(char*));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		g->node_names = p;
		g->node_capacity = new_cap;
	}
	g->node_names[g->node_count] = strdup(name);
	return g->node_count++;
}

static int callgraph_has_edge(const CallGraph* g, int from, int to) {
	for (int i = 0; i < g->edge_count; i++) {
		if (g->edges[i].from == from && g->edges[i].to == to) return 1;
	}
	return 0;
}

static void callgraph_add_edge(CallGraph* g, int from, int to) {
	if (from < 0 || to < 0) return;
	if (callgraph_has_edge(g, from, to)) return;

	if (g->edge_count == g->edge_capacity) {
		int new_cap = g->edge_capacity ? g->edge_capacity * 2 : 32;
		CallGraph_Edge* p = realloc(g->edges, new_cap * sizeof(CallGraph_Edge));
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
	if (node->type == IR_NODE_CALL && node->text) {
		int to_idx = callgraph_add_node(cg, node->text);
		callgraph_add_edge(cg, from_idx, to_idx);
	}
	for (int i = 0; i < node->child_count; i++) {
		collect_calls_in_ir(cg, from_idx, node->children[i]);
	}
}

CallGraph cfg_build_call_graph(const CFG_Analysis* analysis) {
	CallGraph cg;
	memset(&cg, 0, sizeof(CallGraph));

	/* add all defined subprogram names first */
	for (int i = 0; i < analysis->subprogram_count; i++) {
		callgraph_add_node(&cg, analysis->subprograms[i].name);
	}

	for (int i = 0; i < analysis->subprogram_count; i++) {
		const CFG_Subprogram* sp = &analysis->subprograms[i];
		int from_idx = callgraph_add_node(&cg, sp->name);

		for (int b = 0; b < sp->cfg.block_count; b++) {
			const CFG_Block* block = &sp->cfg.blocks[b];
			collect_calls_in_ir(&cg, from_idx, block->ir);
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
	graph->node_names = NULL;
	graph->node_count = 0;
	graph->node_capacity = 0;

	free(graph->edges);
	graph->edges = NULL;
	graph->edge_count = 0;
	graph->edge_capacity = 0;
}
