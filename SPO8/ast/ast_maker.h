#ifndef AST_MAKER_H
#define AST_MAKER_H

#include "ast.h"

typedef struct AST_Wrap {
	char* filename;
	int warning_count;
	char** warnings;
	AST_Node* ast;
} AST_Wrap;

AST_Wrap* create_ast_wrap(const char* input_filename);
void free_ast_wrap(AST_Wrap* wrap);

#endif // AST_MAKER_H