#ifndef AST_H
#define AST_H

#include <stdint.h>

typedef enum {
	AST_LIST,

	AST_TYPE_BOOL,
	AST_TYPE_BYTE,
	AST_TYPE_INT,
	AST_TYPE_UINT,
	AST_TYPE_LONG,
	AST_TYPE_ULONG,
	AST_TYPE_CHAR,
	AST_TYPE_STRING,

	AST_ID,

	AST_CHAR,
	AST_NUM,
	AST_HEX,
	AST_BIT,
	AST_BOOL,
	AST_STRING,

	AST_TYPE_ARRAY,
	AST_TYPE_ARRAY_DIMENTION,

	AST_TYPE_REF,
	AST_ARG_DEF,
	AST_VAR_DECL,
	AST_FIELD_DEF,
	AST_TYPE_DEF,
	AST_INTERFACE_DEF,
	AST_MEMBER_ACCESS,

	AST_UMINUS,
	// AST_NOT (!) can be added

	AST_ASSIG_EQUAL,
	AST_MUL,
	AST_DIV,
	AST_ADD,
	AST_SUB,
	AST_REM,
	AST_L,
	AST_G,
	AST_LE,
	AST_GE,
	AST_EQ,
	AST_NE,
	AST_AND,
	AST_OR,

	AST_WHILE,
	AST_UNTIL,
	AST_REPEAT_WHILE,
	AST_REPEAT_UNTIL,
	AST_BLOCK,
	AST_BREAK,

	AST_IF,
	AST_ELSE,

	AST_FUNC_SIGNATURE,
	AST_FUNC_DEF,
	AST_CALL,
	AST_SLICE,
	AST_RANGE,

	AST_TYPES_COUNT
} NodeType;

typedef struct AST_Loc {
	int first_line;
	int first_column;
	int last_line;
	int last_column;
} AST_Loc;

typedef struct AST {
	NodeType type;
	char* op;
	AST_Loc loc;
	union {
		struct {
			uint32_t num_val;
			char* num_str;
		};
		char* type_name;
		int arr_dimention;
		//char type_postfix[32];
		char* string_value;
		char char_value;
		char* id;

		struct {
			int child_count;
			struct AST** children;
		} compound;
	};
} AST_Node;

void free_ast(AST_Node* node);

AST_Node* create_list_node(AST_Node* first);
AST_Node* append_to_list_node(AST_Node* list, AST_Node* child);

AST_Node* create_node(NodeType type);




AST_Node* create_arg_def_node(AST_Node* id, AST_Node* type_ref);

AST_Node* create_type_ref_node(AST_Node* type);

//AST_Node* create_array_node(AST_Node* type, int dimention);

AST_Node* create_id_node(char* id);

AST_Node* create_char_node(char char_value);
AST_Node* create_string_node(char* string_val);

AST_Node* create_dec_node(char* num_str, NodeType type);

AST_Node* create_type_x_node(char* type_name, NodeType type);

char* expr_to_string(AST_Node* node);


#endif // AST_H
