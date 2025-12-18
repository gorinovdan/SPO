#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ir.h"

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
	free(node);
}

static IRNode* ir_error(const char* message) {
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
	case AST_AND: return "AND";
	case AST_OR: return "OR";
	default: return NULL;
	}
}

static IRNode* ir_from_range(const AST_Node* range);
static IRNode* ir_from_slice_base(const AST_Node* base, const AST_Node* range_list, int is_store);

IRNode* ir_from_expr(const AST_Node* expr) {
	if (!expr) return NULL;

	switch (expr->type) {
	case AST_ID:
		return ir_create_text(IR_NODE_LOAD, expr->id);
	case AST_NUM:
	case AST_HEX:
	case AST_BIT:
	case AST_BOOL:
		return ir_create_text(IR_NODE_CONST, expr->num_str ? expr->num_str : "");
	case AST_STRING:
		return ir_create_text(IR_NODE_CONST, expr->string_value ? expr->string_value : "");
	case AST_CHAR: {
		char tmp[2] = { expr->char_value, '\0' };
		return ir_create_text(IR_NODE_CONST, tmp);
	}
	case AST_UMINUS: {
		IRNode* n = ir_create_op(IR_NODE_UNARY, "NEG");
		if (expr->compound.child_count >= 1) {
			ir_add_child(n, ir_from_expr(expr->compound.children[0]));
		}
		return n;
	}
	case AST_CALL: {
		if (expr->compound.child_count < 1) return ir_error("ERROR(malformed call)");
		const AST_Node* callee = expr->compound.children[0];
		if (!callee || callee->type != AST_ID || !callee->id) {
			return ir_error("ERROR(call target is not identifier)");
		}

		IRNode* call = ir_create_text(IR_NODE_CALL, callee->id);
		if (expr->compound.child_count >= 2 && expr->compound.children[1] && expr->compound.children[1]->type == AST_LIST) {
			const AST_Node* args = expr->compound.children[1];
			for (int i = 0; i < args->compound.child_count; i++) {
				ir_add_child(call, ir_from_expr(args->compound.children[i]));
			}
		}
		return call;
	}
	case AST_SLICE: {
		if (expr->compound.child_count < 2) return ir_error("ERROR(malformed slice)");
		const AST_Node* base = expr->compound.children[0];
		const AST_Node* ranges = expr->compound.children[1];
		return ir_from_slice_base(base, ranges, 0);
	}
	case AST_RANGE:
		return ir_from_range(expr);
	default: {
		const char* op = op_name_for_ast(expr->type);
		if (op) {
			IRNode* n = ir_create_op(IR_NODE_BINARY, op);
			if (expr->compound.child_count >= 1) ir_add_child(n, ir_from_expr(expr->compound.children[0]));
			if (expr->compound.child_count >= 2) ir_add_child(n, ir_from_expr(expr->compound.children[1]));
			return n;
		}
		return ir_error("ERROR(unsupported expression)");
	}
	}
}

static IRNode* ir_from_range(const AST_Node* range) {
	if (!range || range->type != AST_RANGE || range->compound.child_count < 1) {
		return ir_error("ERROR(malformed range)");
	}
	if (range->compound.child_count == 1) {
		return ir_from_expr(range->compound.children[0]);
	}
	IRNode* n = ir_create(IR_NODE_RANGE);
	ir_add_child(n, ir_from_expr(range->compound.children[0]));
	ir_add_child(n, ir_from_expr(range->compound.children[1]));
	return n;
}

static IRNode* ir_from_slice_base(const AST_Node* base, const AST_Node* range_list, int is_store) {
	if (!base) return ir_error("ERROR(malformed slice base)");
	if (base->type != AST_ID || !base->id) {
		return ir_error("ERROR(indexing non-identifier)");
	}

	IRNode* root = ir_create_text(is_store ? IR_NODE_STORE : IR_NODE_LOAD, base->id);
	if (!range_list || range_list->type != AST_LIST) return root;

	for (int i = 0; i < range_list->compound.child_count; i++) {
		IRNode* idx = ir_create(IR_NODE_INDEX);
		ir_add_child(idx, ir_from_range(range_list->compound.children[i]));
		ir_add_child(root, idx);
	}

	return root;
}

IRNode* ir_from_statement(const AST_Node* stmt, char** out_error_message) {
	if (out_error_message) *out_error_message = NULL;
	if (!stmt) return NULL;

	if (stmt->type == AST_BREAK) {
		return NULL;
	}

	/* Assignment expression is encoded as AST_ASSIG_EQUAL node */
	if (stmt->type == AST_ASSIG_EQUAL && stmt->compound.child_count >= 2) {
		const AST_Node* lhs = stmt->compound.children[0];
		const AST_Node* rhs = stmt->compound.children[1];

		IRNode* rhs_ir = ir_from_expr(rhs);
		if (!lhs) {
			if (out_error_message) *out_error_message = xstrdup("ERROR(malformed assignment)");
			ir_free(rhs_ir);
			return ir_error("ERROR(malformed assignment)");
		}

		if (lhs->type == AST_ID && lhs->id) {
			IRNode* store = ir_create_text(IR_NODE_STORE, lhs->id);
			ir_add_child(store, rhs_ir);
			return store;
		}

		if (lhs->type == AST_SLICE && lhs->compound.child_count >= 2) {
			const AST_Node* base = lhs->compound.children[0];
			const AST_Node* ranges = lhs->compound.children[1];
			IRNode* store = ir_from_slice_base(base, ranges, 1);
			ir_add_child(store, rhs_ir);
			return store;
		}

		if (lhs->type == AST_CALL) {
			if (out_error_message) *out_error_message = xstrdup("ERROR(assigning to fuction call)");
			ir_free(rhs_ir);
			return ir_error("ERROR(assigning to fuction call)");
		}

		if (out_error_message) *out_error_message = xstrdup("ERROR(invalid assignment target)");
		ir_free(rhs_ir);
		return ir_error("ERROR(invalid assignment target)");
	}

	/* Expression statement */
	return ir_from_expr(stmt);
}

