#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ir.h"
#include "../cfg/cfg.h"

#define IR_FLAG_AUTO_OBJECT 1

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

IRNode* ir_create(IR_NodeType type) {
	IRNode* n = calloc(1, sizeof(IRNode));
	if (!n) {
		perror("calloc");
		exit(EXIT_FAILURE);
	}
	n->type = type;
	n->const_kind = IR_CONST_UNKNOWN;
	return n;
}

IRNode* ir_create_op(IR_NodeType type, const char* op) {
	IRNode* n = ir_create(type);
	n->op = xstrdup(op);
	return n;
}

IRNode* ir_create_text(IR_NodeType type, const char* text) {
	IRNode* n = ir_create(type);
	n->text = xstrdup(text);
	return n;
}

void ir_add_child(IRNode* parent, IRNode* child) {
	if (!parent || !child) return;
	if (parent->child_count == parent->child_capacity) {
		int new_cap = parent->child_capacity ? parent->child_capacity * 2 : 4;
		IRNode** p = realloc(parent->children, new_cap * sizeof(IRNode*));
		if (!p) {
			perror("realloc");
			exit(EXIT_FAILURE);
		}
		parent->children = p;
		parent->child_capacity = new_cap;
	}
	parent->children[parent->child_count++] = child;
}

void ir_free(IRNode* node) {
	if (!node) return;
	for (int i = 0; i < node->child_count; i++) {
		ir_free(node->children[i]);
	}
	free(node->children);
	free(node->op);
	free(node->text);
	free(node->owner_name);
	free(node->type_name);
	free(node);
}

static IRNode* ir_error(const char* message, char** out_error_message) {
	if (out_error_message && !*out_error_message) {
		*out_error_message = xstrdup(message ? message : "ERROR");
	}
	return ir_create_text(IR_NODE_ERROR, message ? message : "ERROR");
}

static const char* op_name_for_ast(NodeType type) {
	switch (type) {
	case AST_ADD: return "ADD";
	case AST_SUB: return "SUB";
	case AST_MUL: return "MUL";
	case AST_DIV: return "DIV";
	case AST_REM: return "REM";
	case AST_L: return "LT";
	case AST_G: return "GT";
	case AST_LE: return "LE";
	case AST_GE: return "GE";
	case AST_EQ: return "EQ";
	case AST_NE: return "NE";
	case AST_AND: return "AND_OP";
	case AST_OR: return "OR_OP";
	default: return NULL;
	}
}

static const CFG_UserType* find_type(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return NULL;
	for (int i = 0; i < analysis->type_count; i++) {
		if (analysis->types[i].name && strcmp(analysis->types[i].name, name) == 0) {
			return &analysis->types[i];
		}
	}
	return NULL;
}

static const CFG_Field* find_field(const CFG_UserType* type, const char* name) {
	if (!type || !name) return NULL;
	for (int i = 0; i < type->field_count; i++) {
		if (type->fields[i].name && strcmp(type->fields[i].name, name) == 0) {
			return &type->fields[i];
		}
	}
	return NULL;
}

static const CFG_Method* find_method(const CFG_UserType* type, const char* name) {
	if (!type || !name) return NULL;
	for (int i = 0; i < type->method_count; i++) {
		if (type->methods[i].name && strcmp(type->methods[i].name, name) == 0) {
			return &type->methods[i];
		}
	}
	return NULL;
}

static const CFG_Subprogram* find_global_subprogram(const CFG_Analysis* analysis, const char* name) {
	if (!analysis || !name) return NULL;
	for (int i = 0; i < analysis->subprogram_count; i++) {
		const CFG_Subprogram* sp = &analysis->subprograms[i];
		if (sp->is_method) continue;
		if (sp->name && strcmp(sp->name, name) == 0) return sp;
	}
	return NULL;
}

static const CFG_Symbol* find_symbol(const CFG_Subprogram* sp, const char* name) {
	if (!sp || !name) return NULL;
	for (int i = 0; i < sp->symbol_count; i++) {
		if (sp->symbols[i].name && strcmp(sp->symbols[i].name, name) == 0) {
			return &sp->symbols[i];
		}
	}
	return NULL;
}

static int is_object_like_type(const CFG_Analysis* analysis, const char* type_name) {
	return find_type(analysis, type_name) != NULL;
}

static char* make_dispatch_name(const char* owner_type, const char* method_name) {
	int len = snprintf(NULL, 0, "__dispatch_%s_%s", owner_type ? owner_type : "type", method_name ? method_name : "method") + 1;
	char* res = malloc((size_t)len);
	if (!res) {
		perror("malloc");
		exit(EXIT_FAILURE);
	}
	snprintf(res, (size_t)len, "__dispatch_%s_%s", owner_type ? owner_type : "type", method_name ? method_name : "method");
	return res;
}

static IRNode* ir_from_range(const AST_Node* range, const IR_BuildContext* ctx, char** out_error_message);
static IRNode* ir_from_member_access(const AST_Node* expr, const IR_BuildContext* ctx, char** out_error_message);
static IRNode* ir_from_slice_base(const AST_Node* base, const AST_Node* range_list, int is_store, const IR_BuildContext* ctx, char** out_error_message);

IRNode* ir_from_expr_ctx(const AST_Node* expr, const IR_BuildContext* ctx, char** out_error_message) {
	if (out_error_message) *out_error_message = NULL;
	if (!expr) return NULL;

	switch (expr->type) {
	case AST_ID: {
		IRNode* n = ir_create_text(IR_NODE_LOAD, expr->id);
		const CFG_Symbol* sym = (ctx && ctx->subprogram) ? find_symbol(ctx->subprogram, expr->id) : NULL;
		if (sym && sym->type) {
			n->type_name = xstrdup(sym->type);
		}
		return n;
	}
	case AST_NUM:
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL: {
		IRNode* n = ir_create_text(IR_NODE_CONST, expr->num_str ? expr->num_str : "");
		n->const_kind = (expr->type == AST_BOOL) ? IR_CONST_BOOL : IR_CONST_NUMBER;
		n->type_name = xstrdup((expr->type == AST_BOOL) ? "bool" : "int");
		return n;
	}
	case AST_STRING: {
		IRNode* n = ir_create_text(IR_NODE_CONST, expr->string_value ? expr->string_value : "");
		n->const_kind = IR_CONST_STRING;
		n->type_name = xstrdup("string");
		return n;
	}
	case AST_CHAR: {
		char tmp[2] = { expr->char_value, '\0' };
		IRNode* n = ir_create_text(IR_NODE_CONST, tmp);
		n->const_kind = IR_CONST_CHAR;
		n->type_name = xstrdup("char");
		return n;
	}
	case AST_UMINUS: {
		IRNode* n = ir_create_op(IR_NODE_UNARY, "NEG");
		if (expr->compound.child_count >= 1) {
			IRNode* child = ir_from_expr_ctx(expr->compound.children[0], ctx, out_error_message);
			ir_add_child(n, child);
			if (child && child->type_name) n->type_name = xstrdup(child->type_name);
		}
		return n;
	}
	case AST_CALL: {
		if (expr->compound.child_count < 1) {
			return ir_error("ERROR(malformed call)", out_error_message);
		}
		const AST_Node* callee = expr->compound.children[0];
		if (callee && callee->type == AST_MEMBER_ACCESS) {
			if (callee->compound.child_count < 2) {
				return ir_error("ERROR(malformed member call)", out_error_message);
			}
			const AST_Node* member = callee->compound.children[1];
			if (!member || member->type != AST_ID || !member->id) {
				return ir_error("ERROR(member call target is not identifier)", out_error_message);
			}
			IRNode* receiver = ir_from_expr_ctx(callee->compound.children[0], ctx, out_error_message);
			if (!receiver || !receiver->type_name) {
				ir_free(receiver);
				return ir_error("ERROR(method receiver type is unknown)", out_error_message);
			}
			const CFG_UserType* owner_type = ctx ? find_type(ctx->analysis, receiver->type_name) : NULL;
			if (!owner_type) {
				ir_free(receiver);
				return ir_error("ERROR(method receiver is not user type)", out_error_message);
			}
			const CFG_Method* method = find_method(owner_type, member->id);
			if (!method) {
				ir_free(receiver);
				return ir_error("ERROR(unknown method)", out_error_message);
			}
			char* dispatch_name = make_dispatch_name(owner_type->name, method->name);
			IRNode* call = ir_create_text(IR_NODE_METHOD_CALL, dispatch_name);
			free(dispatch_name);
			call->owner_name = xstrdup(owner_type->name);
			call->type_name = xstrdup(method->return_type ? method->return_type : "");
			ir_add_child(call, receiver);
			if (expr->compound.child_count >= 2 && expr->compound.children[1] && expr->compound.children[1]->type == AST_LIST) {
				const AST_Node* args = expr->compound.children[1];
				for (int i = 0; i < args->compound.child_count; i++) {
					ir_add_child(call, ir_from_expr_ctx(args->compound.children[i], ctx, out_error_message));
				}
			}
			return call;
		}

		if (!callee || callee->type != AST_ID || !callee->id) {
			return ir_error("ERROR(call target is not identifier)", out_error_message);
		}

		IRNode* call = ir_create_text(IR_NODE_CALL, callee->id);
		const CFG_Subprogram* sp = (ctx && ctx->analysis) ? find_global_subprogram(ctx->analysis, callee->id) : NULL;
		if (sp && sp->return_type) {
			call->type_name = xstrdup(sp->return_type);
		}
		else if (strcmp(callee->id, "read") == 0) {
			call->type_name = xstrdup("int");
		}
		else {
			call->type_name = xstrdup("int");
		}
		if (expr->compound.child_count >= 2 && expr->compound.children[1] && expr->compound.children[1]->type == AST_LIST) {
			const AST_Node* args = expr->compound.children[1];
			for (int i = 0; i < args->compound.child_count; i++) {
				ir_add_child(call, ir_from_expr_ctx(args->compound.children[i], ctx, out_error_message));
			}
		}
		return call;
	}
	case AST_MEMBER_ACCESS:
		return ir_from_member_access(expr, ctx, out_error_message);
	case AST_SLICE: {
		if (expr->compound.child_count < 2) return ir_error("ERROR(malformed slice)", out_error_message);
		const AST_Node* base = expr->compound.children[0];
		const AST_Node* ranges = expr->compound.children[1];
		return ir_from_slice_base(base, ranges, 0, ctx, out_error_message);
	}
	case AST_RANGE:
		return ir_from_range(expr, ctx, out_error_message);
	default: {
		const char* op = op_name_for_ast(expr->type);
		if (op) {
			IRNode* n = ir_create_op(IR_NODE_BINARY, op);
			if (expr->compound.child_count >= 1) ir_add_child(n, ir_from_expr_ctx(expr->compound.children[0], ctx, out_error_message));
			if (expr->compound.child_count >= 2) ir_add_child(n, ir_from_expr_ctx(expr->compound.children[1], ctx, out_error_message));
			if (expr->type == AST_L || expr->type == AST_G || expr->type == AST_LE || expr->type == AST_GE ||
				expr->type == AST_EQ || expr->type == AST_NE || expr->type == AST_AND || expr->type == AST_OR) {
				n->type_name = xstrdup("bool");
			}
			else {
				n->type_name = xstrdup("int");
			}
			return n;
		}
		return ir_error("ERROR(unsupported expression)", out_error_message);
	}
	}
}

static IRNode* ir_from_member_access(const AST_Node* expr, const IR_BuildContext* ctx, char** out_error_message) {
	if (!expr || expr->type != AST_MEMBER_ACCESS || expr->compound.child_count < 2) {
		return ir_error("ERROR(malformed member access)", out_error_message);
	}
	const AST_Node* base = expr->compound.children[0];
	const AST_Node* member = expr->compound.children[1];
	if (!member || member->type != AST_ID || !member->id) {
		return ir_error("ERROR(malformed member name)", out_error_message);
	}

	IRNode* receiver = ir_from_expr_ctx(base, ctx, out_error_message);
	if (!receiver || !receiver->type_name) {
		ir_free(receiver);
		return ir_error("ERROR(member receiver type is unknown)", out_error_message);
	}

	const CFG_UserType* type = ctx ? find_type(ctx->analysis, receiver->type_name) : NULL;
	if (!type) {
		ir_free(receiver);
		return ir_error("ERROR(member receiver is not user type)", out_error_message);
	}

	const CFG_Field* field = find_field(type, member->id);
	if (!field) {
		ir_free(receiver);
		return ir_error("ERROR(unknown field)", out_error_message);
	}

	IRNode* load = ir_create_text(IR_NODE_FIELD_LOAD, member->id);
	load->owner_name = xstrdup(type->name);
	load->type_name = xstrdup(field->type ? field->type : "");
	load->offset = field->slot_index;
	ir_add_child(load, receiver);
	return load;
}

static IRNode* ir_from_range(const AST_Node* range, const IR_BuildContext* ctx, char** out_error_message) {
	if (!range || range->type != AST_RANGE || range->compound.child_count < 1) {
		return ir_error("ERROR(malformed range)", out_error_message);
	}
	if (range->compound.child_count == 1) {
		return ir_from_expr_ctx(range->compound.children[0], ctx, out_error_message);
	}
	IRNode* n = ir_create(IR_NODE_RANGE);
	ir_add_child(n, ir_from_expr_ctx(range->compound.children[0], ctx, out_error_message));
	ir_add_child(n, ir_from_expr_ctx(range->compound.children[1], ctx, out_error_message));
	n->type_name = xstrdup("int");
	return n;
}

static IRNode* ir_from_slice_base(const AST_Node* base, const AST_Node* range_list, int is_store, const IR_BuildContext* ctx, char** out_error_message) {
	if (!base) return ir_error("ERROR(malformed slice base)", out_error_message);
	if (base->type != AST_ID || !base->id) {
		return ir_error("ERROR(indexing non-identifier)", out_error_message);
	}

	IRNode* root = ir_create_text(is_store ? IR_NODE_STORE : IR_NODE_LOAD, base->id);
	const CFG_Symbol* sym = (ctx && ctx->subprogram) ? find_symbol(ctx->subprogram, base->id) : NULL;
	if (sym && sym->type) {
		root->type_name = xstrdup(sym->type);
	}
	if (!range_list || range_list->type != AST_LIST) return root;

	for (int i = 0; i < range_list->compound.child_count; i++) {
		IRNode* idx = ir_create(IR_NODE_INDEX);
		ir_add_child(idx, ir_from_range(range_list->compound.children[i], ctx, out_error_message));
		ir_add_child(root, idx);
	}
	return root;
}

IRNode* ir_from_statement_ctx(const AST_Node* stmt, const IR_BuildContext* ctx, char** out_error_message) {
	if (out_error_message) *out_error_message = NULL;
	if (!stmt) return NULL;

	if (stmt->type == AST_BREAK) {
		return NULL;
	}

	if (stmt->type == AST_VAR_DECL) {
		if (stmt->compound.child_count < 2) {
			return ir_error("ERROR(malformed variable declaration)", out_error_message);
		}
		const AST_Node* id_node = stmt->compound.children[0];
		const AST_Node* type_node = stmt->compound.children[1];
		if (!id_node || id_node->type != AST_ID || !id_node->id) {
			return ir_error("ERROR(malformed variable declaration)", out_error_message);
		}
		char* type_name = expr_to_string((AST_Node*)type_node);
		IRNode* decl = ir_create_text(IR_NODE_DECL, id_node->id);
		decl->type_name = type_name;
		if (ctx && ctx->analysis) {
			const CFG_UserType* user_type = find_type(ctx->analysis, decl->type_name);
			if (user_type && !user_type->is_interface && stmt->compound.child_count < 3) {
				decl->flags |= IR_FLAG_AUTO_OBJECT;
			}
		}
		if (stmt->compound.child_count >= 3) {
			ir_add_child(decl, ir_from_expr_ctx(stmt->compound.children[2], ctx, out_error_message));
		}
		return decl;
	}

	if (stmt->type == AST_ASSIG_EQUAL && stmt->compound.child_count >= 2) {
		const AST_Node* lhs = stmt->compound.children[0];
		const AST_Node* rhs = stmt->compound.children[1];
		IRNode* rhs_ir = ir_from_expr_ctx(rhs, ctx, out_error_message);
		if (!lhs) {
			ir_free(rhs_ir);
			return ir_error("ERROR(malformed assignment)", out_error_message);
		}

		if (lhs->type == AST_ID && lhs->id) {
			IRNode* store = ir_create_text(IR_NODE_STORE, lhs->id);
			const CFG_Symbol* sym = (ctx && ctx->subprogram) ? find_symbol(ctx->subprogram, lhs->id) : NULL;
			if (sym && sym->type) {
				store->type_name = xstrdup(sym->type);
			}
			ir_add_child(store, rhs_ir);
			return store;
		}

		if (lhs->type == AST_SLICE && lhs->compound.child_count >= 2) {
			const AST_Node* base = lhs->compound.children[0];
			const AST_Node* ranges = lhs->compound.children[1];
			IRNode* store = ir_from_slice_base(base, ranges, 1, ctx, out_error_message);
			ir_add_child(store, rhs_ir);
			return store;
		}

		if (lhs->type == AST_MEMBER_ACCESS) {
			IRNode* member = ir_from_member_access(lhs, ctx, out_error_message);
			if (!member || member->type != IR_NODE_FIELD_LOAD) {
				ir_free(member);
				ir_free(rhs_ir);
				return ir_error("ERROR(invalid member assignment target)", out_error_message);
			}
			IRNode* store = ir_create_text(IR_NODE_FIELD_STORE, member->text);
			store->owner_name = xstrdup(member->owner_name);
			store->type_name = xstrdup(member->type_name);
			store->offset = member->offset;
			if (member->child_count >= 1) {
				ir_add_child(store, member->children[0]);
				member->children[0] = NULL;
				member->child_count = 0;
			}
			ir_add_child(store, rhs_ir);
			ir_free(member);
			return store;
		}

		ir_free(rhs_ir);
		return ir_error("ERROR(invalid assignment target)", out_error_message);
	}

	return ir_from_expr_ctx(stmt, ctx, out_error_message);
}
