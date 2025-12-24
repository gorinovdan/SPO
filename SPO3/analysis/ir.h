#ifndef IR_H
#define IR_H

#include "../ast/ast.h"

typedef enum IR_NodeType {
	IR_NODE_LIST,
	IR_NODE_CONST,
	IR_NODE_LOAD,
	IR_NODE_STORE,
	IR_NODE_UNARY,
	IR_NODE_BINARY,
	IR_NODE_CALL,
	IR_NODE_INDEX,
	IR_NODE_RANGE,
	IR_NODE_ERROR
} IR_NodeType;

typedef enum IR_ConstKind {
	IR_CONST_UNKNOWN = 0,
	IR_CONST_NUMBER,
	IR_CONST_BOOL,
	IR_CONST_CHAR,
	IR_CONST_STRING
} IR_ConstKind;

typedef struct IRNode {
	IR_NodeType type;
	char* op;   /* e.g. ADD, SUB, LT, NEG, ... */
	char* text; /* variable name / constant value / call name / error text */
	IR_ConstKind const_kind;

	struct IRNode** children;
	int child_count;
	int child_capacity;
} IRNode;

IRNode* ir_create(IR_NodeType type);
IRNode* ir_create_op(IR_NodeType type, const char* op);
IRNode* ir_create_text(IR_NodeType type, const char* text);
void ir_add_child(IRNode* parent, IRNode* child);
void ir_free(IRNode* node);

/* Build IR (operation tree) from AST nodes */
IRNode* ir_from_expr(const AST_Node* expr);
IRNode* ir_from_statement(const AST_Node* stmt, char** out_error_message);

#endif /* IR_H */
