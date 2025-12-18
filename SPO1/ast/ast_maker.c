#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "ast_maker.h"

extern int yyparse();
extern FILE* yyin;
extern AST_Node* root;

AST_Wrap* create_ast_wrap(const char* input_filename) {
	FILE* in = fopen(input_filename, "r");
	if (!in) {
		printf("Cannot open input file %s\n", input_filename);
		return NULL;
	}
	yyin = in;
	yyparse();
	fclose(in);

	AST_Wrap* wrap = malloc(sizeof(AST_Wrap));
	wrap->ast = root;
	wrap->filename = malloc(strlen(input_filename));
	strcpy(wrap->filename, input_filename);

	// Change later to actual warnings
	wrap->warning_count = 0;
	wrap->warnings = NULL;

	return wrap;
}

void free_ast_wrap(AST_Wrap* wrap) {
	free(wrap->filename);
	for (int i = 0; i < wrap->warning_count; i++) {
		if (wrap->warnings[i]) free(wrap->warnings[i]);
	}
	free(wrap->warnings);
	free_ast(wrap->ast);
	free(wrap);
}