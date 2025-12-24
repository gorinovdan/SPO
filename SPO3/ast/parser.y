
%{
#include <stdio.h>
#include "ast.h"

int yylex();
int yyerror(const char *s);

AST_Node *root;

#define SET_LOC(node_ptr, src_loc) do { \
	if ((node_ptr) != NULL) { \
		(node_ptr)->loc.first_line = (src_loc).first_line; \
		(node_ptr)->loc.first_column = (src_loc).first_column; \
		(node_ptr)->loc.last_line = (src_loc).last_line; \
		(node_ptr)->loc.last_column = (src_loc).last_column; \
	} \
} while (0)

%}

%glr-parser
%expect 14

%locations

%token OTHER IDENTIFIER EMPTY_BRACKETS
%token ARRAY OF IF THEN ELSE BEGIN_T END WHILE UNTIL BREAK DEF
%token AND_OP OR_OP LE_OP GE_OP EQ_OP NE_OP UMINUS
%token BOOL_VAL STRING_VAL CHAR_VAL HEX_VAL BITS_VAL DEC_VAL
%token BOOL BYTE INT UINT LONG ULONG CHAR STRING

%type <node> literal builtin identifier array type_ref arg_def arg_def_list unary_operator
assignment_operator primary_expr postfix_expr argument_expr_list unary_expr multiplicative_expr additive_expr
relational_expr equality_expr logical_and_expr logical_or_expr assignment_expr statement statement_set slice_range slice_range_list
selection_statement iteration_statement in_block_set block_statement func_signature func_def source_item source_item_set source

%type <num_str> DEC_VAL HEX_VAL BITS_VAL BOOL_VAL
%type <string_val> STRING_VAL
%type <id> IDENTIFIER
%type <char_val> CHAR_VAL
%type <type_name> BOOL BYTE INT UINT LONG ULONG CHAR STRING
%type <brackets> EMPTY_BRACKETS

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%union {
	AST_Node *node;

	//uint32_t num_val;
	char *num_str;
	char *type_name;
	char *string_val;
	char char_val;

	char *id;

	char *brackets;
}

%start source

%%

source
	: source_item_set			{ root = $1; }
	;

source_item
	: func_def					{ $$ = $1; }
	;

source_item_set
	: source_item						{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| source_item_set source_item		{ $$ = append_to_list_node($1, $2); SET_LOC($$, @$); }
	;

func_def
	: DEF func_signature statement_set END		{ $$ = create_node(AST_FUNC_DEF); SET_LOC($$, @$); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| DEF func_signature END					{ $$ = create_node(AST_FUNC_DEF); SET_LOC($$, @$); append_to_list_node($$, $2); }
	;

statement
	: selection_statement			{ $$ = $1; }
	| iteration_statement			{ $$ = $1; }
	| BREAK ';'						{ $$ = create_node(AST_BREAK); SET_LOC($$, @1); $$->op = "break"; }
	| assignment_expr ';'			{ $$ = $1; }
	| block_statement				{ $$ = $1; }
	;

statement_set
	: statement						{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| statement_set statement		{ $$ = append_to_list_node($1, $2); SET_LOC($$, @$); }
	;

in_block_set
	: statement						{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| source_item					{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| in_block_set statement		{ $$ = append_to_list_node($1, $2); SET_LOC($$, @$); }
	| in_block_set source_item		{ $$ = append_to_list_node($1, $2); SET_LOC($$, @$); }
	;

selection_statement
	: IF assignment_expr THEN statement ELSE statement	{
																			$$ = create_node(AST_IF);
																			SET_LOC($$, @$);
																			append_to_list_node($$, $2); 
																			append_to_list_node($$, $4);
																			AST_Node* else_node = create_node(AST_ELSE);
																			SET_LOC(else_node, @5);
																			append_to_list_node(else_node, $6);
																			append_to_list_node($$, else_node);
																		}
	| IF assignment_expr THEN statement %prec LOWER_THAN_ELSE			{
																			$$ = create_node(AST_IF);
																			SET_LOC($$, @$);
																			append_to_list_node($$, $2);
																			append_to_list_node($$, $4);
																		}
	;

iteration_statement
	: WHILE assignment_expr statement_set END		{ $$ = create_node(AST_WHILE); SET_LOC($$, @$); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| WHILE assignment_expr END						{ $$ = create_node(AST_WHILE); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| UNTIL assignment_expr statement_set END		{ $$ = create_node(AST_UNTIL); SET_LOC($$, @$); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| UNTIL assignment_expr END						{ $$ = create_node(AST_UNTIL); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| statement WHILE assignment_expr ';'			{ $$ = create_node(AST_REPEAT_WHILE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| statement UNTIL assignment_expr ';'			{ $$ = create_node(AST_REPEAT_UNTIL); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

block_statement
	: BEGIN_T in_block_set END		{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| BEGIN_T in_block_set '}'		{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| '{' in_block_set END			{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| '{' in_block_set '}'			{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); append_to_list_node($$, $2); }
	| BEGIN_T END						{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); }
	| BEGIN_T '}'						{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); }
	| '{' END						{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); }
	| '{' '}'						{ $$ = create_node(AST_BLOCK); SET_LOC($$, @$); }
	;

slice_range
	: assignment_expr							{ $$ = create_node(AST_RANGE); SET_LOC($$, @$); append_to_list_node($$, $1); }
	| assignment_expr '.' '.' assignment_expr	{ $$ = create_node(AST_RANGE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $4); }
	;

slice_range_list
	: slice_range								{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| slice_range_list ',' slice_range			{ $$ = append_to_list_node($1, $3); SET_LOC($$, @$); }
	;
		
primary_expr
	: identifier					{ $$ = $1; }
	| literal						{ $$ = $1; }	
	| '(' assignment_expr ')'		{ $$ = $2; }
	;

postfix_expr
	: primary_expr								{ $$ = $1; }
	| postfix_expr EMPTY_BRACKETS				{ $$ = create_node(AST_CALL); SET_LOC($$, @$); append_to_list_node($$, $1); }
	| postfix_expr '(' argument_expr_list ')'	{ $$ = create_node(AST_CALL); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| postfix_expr '[' slice_range_list ']'		{ $$ = create_node(AST_SLICE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

argument_expr_list
	: assignment_expr								{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| argument_expr_list ',' assignment_expr		{ $$ = append_to_list_node($1, $3); SET_LOC($$, @$); }
	;

unary_expr
	: postfix_expr					{ $$ = $1; }
	| unary_operator unary_expr		{ $$ = append_to_list_node($1, $2); SET_LOC($$, @$); }
	;

multiplicative_expr
	: unary_expr							{ $$ = $1; }
	| multiplicative_expr '*' unary_expr	{ $$ = create_node(AST_MUL); SET_LOC($$, @$); $$->op = "*"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| multiplicative_expr '/' unary_expr	{ $$ = create_node(AST_DIV); SET_LOC($$, @$); $$->op = "/"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| multiplicative_expr '%' unary_expr	{ $$ = create_node(AST_REM); SET_LOC($$, @$); $$->op = "%"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

additive_expr
	: multiplicative_expr						{ $$ = $1; }
	| additive_expr '+' multiplicative_expr		{ $$ = create_node(AST_ADD); SET_LOC($$, @$); $$->op = "+"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| additive_expr '-' multiplicative_expr		{ $$ = create_node(AST_SUB); SET_LOC($$, @$); $$->op = "-"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

relational_expr
	: additive_expr							{ $$ = $1; }
	| relational_expr '<' additive_expr		{ $$ = create_node(AST_L); SET_LOC($$, @$); $$->op = "<"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr '>' additive_expr		{ $$ = create_node(AST_G); SET_LOC($$, @$); $$->op = ">"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr LE_OP additive_expr	{ $$ = create_node(AST_LE); SET_LOC($$, @$); $$->op = "<="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr GE_OP additive_expr	{ $$ = create_node(AST_GE); SET_LOC($$, @$); $$->op = ">="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

equality_expr
	: relational_expr						{ $$ = $1; }
	| equality_expr EQ_OP relational_expr	{ $$ = create_node(AST_EQ); SET_LOC($$, @$); $$->op = "=="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| equality_expr NE_OP relational_expr	{ $$ = create_node(AST_NE); SET_LOC($$, @$); $$->op = "!="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

logical_and_expr
	: equality_expr								{ $$ = $1; }
	| logical_and_expr AND_OP equality_expr		{ $$ = create_node(AST_AND); SET_LOC($$, @$); $$->op = "&&"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

logical_or_expr
	: logical_and_expr							{ $$ = $1; }
	| logical_or_expr OR_OP logical_and_expr	{ $$ = create_node(AST_OR); SET_LOC($$, @$); $$->op = "||"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

assignment_expr
	: logical_or_expr									{ $$ = $1; }
	| postfix_expr assignment_operator assignment_expr	{ $$ = $2; append_to_list_node($$, $1); append_to_list_node($$, $3); SET_LOC($$, @$); }
	;

assignment_operator
	: '='			{ $$ = create_node(AST_ASSIG_EQUAL); SET_LOC($$, @1); $$->op = "="; }
	;

unary_operator
	: UMINUS		{ $$ = create_node(AST_UMINUS); SET_LOC($$, @1); $$->op = "neg"; }
	;

literal
	: BOOL_VAL				{ $$ = create_dec_node($1, AST_BOOL); SET_LOC($$, @1); }
	| STRING_VAL			{ $$ = create_string_node($1); SET_LOC($$, @1); }
	| CHAR_VAL				{ $$ = create_char_node($1); SET_LOC($$, @1); }
	| HEX_VAL				{ $$ = create_dec_node($1, AST_HEX); SET_LOC($$, @1); }
	| BITS_VAL				{ $$ = create_dec_node($1, AST_BIT); SET_LOC($$, @1); }
	| DEC_VAL				{ $$ = create_dec_node($1, AST_NUM); SET_LOC($$, @1); }
	;

func_signature
	: identifier '(' arg_def_list ')'				{ $$ = create_node(AST_FUNC_SIGNATURE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| identifier EMPTY_BRACKETS						{ $$ = create_node(AST_FUNC_SIGNATURE); SET_LOC($$, @$); append_to_list_node($$, $1); }
	| identifier '(' arg_def_list ')' OF type_ref	{ $$ = create_node(AST_FUNC_SIGNATURE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $3); append_to_list_node($$, $6); }	
	| identifier EMPTY_BRACKETS OF type_ref			{ $$ = create_node(AST_FUNC_SIGNATURE); SET_LOC($$, @$); append_to_list_node($$, $1); append_to_list_node($$, $4); }
	;

arg_def_list
	: arg_def						{ $$ = create_list_node($1); SET_LOC($$, @$); }
	| arg_def_list ',' arg_def		{ $$ = append_to_list_node($1, $3); SET_LOC($$, @$); }
	;

arg_def
	: identifier					{ $$ = create_arg_def_node($1, NULL); SET_LOC($$, @$); }
	| identifier OF type_ref		{ $$ = create_arg_def_node($1, $3); SET_LOC($$, @$); }
	;

type_ref
	: builtin				{ $$ = create_type_ref_node($1); SET_LOC($$, @$); }
	| identifier			{ $$ = create_type_ref_node($1); SET_LOC($$, @$); }
	| array					{ $$ = create_type_ref_node($1); SET_LOC($$, @$); }
	;

array
	: builtin ARRAY '[' DEC_VAL ']'		{ $$ = create_node(AST_TYPE_ARRAY); SET_LOC($$, @$); append_to_list_node($$, $1); AST_Node* dim = create_dec_node($4, AST_NUM); SET_LOC(dim, @4); append_to_list_node($$, dim); }
	| identifier ARRAY '[' DEC_VAL ']'	{ $$ = create_node(AST_TYPE_ARRAY); SET_LOC($$, @$); append_to_list_node($$, $1); AST_Node* dim = create_dec_node($4, AST_NUM); SET_LOC(dim, @4); append_to_list_node($$, dim); }
	;

builtin
	: BOOL			{ $$ = create_type_x_node($1, AST_TYPE_BOOL); SET_LOC($$, @1); }
	| BYTE			{ $$ = create_type_x_node($1, AST_TYPE_BYTE); SET_LOC($$, @1); }
	| INT			{ $$ = create_type_x_node($1, AST_TYPE_INT); SET_LOC($$, @1); }
	| UINT			{ $$ = create_type_x_node($1, AST_TYPE_UINT); SET_LOC($$, @1); }
	| LONG			{ $$ = create_type_x_node($1, AST_TYPE_LONG); SET_LOC($$, @1); }
	| ULONG			{ $$ = create_type_x_node($1, AST_TYPE_ULONG); SET_LOC($$, @1); }
	| CHAR			{ $$ = create_type_x_node($1, AST_TYPE_CHAR); SET_LOC($$, @1); }
	| STRING		{ $$ = create_type_x_node($1, AST_TYPE_STRING); SET_LOC($$, @1); }
	;

identifier
	: IDENTIFIER	{ $$ = create_id_node($1); SET_LOC($$, @1); }
	;

%%

int yyerror(const char *s) {
    /* yylloc is available because of %locations */
    fprintf(stderr, "Syntax error at %d:%d — %s\n",
            yylloc.first_line, yylloc.first_column, s);
    return 0;
}
