
%{
#include <stdio.h>
#include "ast.h"

int yylex();
int yyerror(const char *s);

AST_Node *root;

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
	: source_item						{ $$ = create_list_node($1); }
	| source_item_set source_item		{ $$ = append_to_list_node($1, $2); }
	;

func_def
	: DEF func_signature statement_set END		{ $$ = create_node(AST_FUNC_DEF); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| DEF func_signature END					{ $$ = create_node(AST_FUNC_DEF); append_to_list_node($$, $2); }
	;

statement
	: selection_statement			{ $$ = $1; }
	| iteration_statement			{ $$ = $1; }
	| BREAK ';'						{ $$ = create_node(AST_BREAK); $$->op = "break"; }
	| assignment_expr ';'			{ $$ = $1; }
	| block_statement				{ $$ = $1; }
	;

statement_set
	: statement						{ $$ = create_list_node($1); }
	| statement_set statement		{ $$ = append_to_list_node($1, $2); }
	;

in_block_set
	: statement						{ $$ = create_list_node($1); }
	| source_item					{ $$ = create_list_node($1); }
	| in_block_set statement		{ $$ = append_to_list_node($1, $2); }
	| in_block_set source_item		{ $$ = append_to_list_node($1, $2); }
	;

selection_statement
	: IF assignment_expr THEN statement ELSE statement	{
																			$$ = create_node(AST_IF);
																			append_to_list_node($$, $2); 
																			append_to_list_node($$, $4);
																			append_to_list_node($$, append_to_list_node(
																				create_node(AST_ELSE), $6
																			));
																		}
	| IF assignment_expr THEN statement %prec LOWER_THAN_ELSE			{
																			$$ = create_node(AST_IF);
																			append_to_list_node($$, $2);
																			append_to_list_node($$, $4);
																		}
	;

iteration_statement
	: WHILE assignment_expr statement_set END		{ $$ = create_node(AST_WHILE); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| WHILE assignment_expr END						{ $$ = create_node(AST_WHILE); append_to_list_node($$, $2); }
	| UNTIL assignment_expr statement_set END		{ $$ = create_node(AST_UNTIL); append_to_list_node($$, $2); append_to_list_node($$, $3); }
	| UNTIL assignment_expr END						{ $$ = create_node(AST_UNTIL); append_to_list_node($$, $2); }
	| statement WHILE assignment_expr ';'			{ $$ = create_node(AST_REPEAT_WHILE); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| statement UNTIL assignment_expr ';'			{ $$ = create_node(AST_REPEAT_UNTIL); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

block_statement
	: BEGIN_T in_block_set END		{ $$ = create_node(AST_BLOCK); append_to_list_node($$, $2); }
	| BEGIN_T in_block_set '}'		{ $$ = create_node(AST_BLOCK); append_to_list_node($$, $2); }
	| '{' in_block_set END			{ $$ = create_node(AST_BLOCK); append_to_list_node($$, $2); }
	| '{' in_block_set '}'			{ $$ = create_node(AST_BLOCK); append_to_list_node($$, $2); }
	| BEGIN_T END						{ $$ = create_node(AST_BLOCK); }
	| BEGIN_T '}'						{ $$ = create_node(AST_BLOCK); }
	| '{' END						{ $$ = create_node(AST_BLOCK); }
	| '{' '}'						{ $$ = create_node(AST_BLOCK); }
	;

slice_range
	: assignment_expr							{ $$ = create_node(AST_RANGE); append_to_list_node($$, $1); }
	| assignment_expr '.' '.' assignment_expr	{ $$ = create_node(AST_RANGE); append_to_list_node($$, $1); append_to_list_node($$, $4); }
	;

slice_range_list
	: slice_range								{ $$ = create_list_node($1); }
	| slice_range_list ',' slice_range			{ $$ = append_to_list_node($1, $3); }
	;
		
primary_expr
	: identifier					{ $$ = $1; }
	| literal						{ $$ = $1; }	
	| '(' assignment_expr ')'		{ $$ = $2; }
	;

postfix_expr
	: primary_expr								{ $$ = $1; }
	| postfix_expr EMPTY_BRACKETS				{ $$ = create_node(AST_CALL); append_to_list_node($$, $1); }
	| postfix_expr '(' argument_expr_list ')'	{ $$ = create_node(AST_CALL); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| postfix_expr '[' slice_range_list ']'		{ $$ = create_node(AST_SLICE); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

argument_expr_list
	: assignment_expr								{ $$ = create_list_node($1); }
	| argument_expr_list ',' assignment_expr		{ $$ = append_to_list_node($1, $3); }
	;

unary_expr
	: postfix_expr					{ $$ = $1; }
	| unary_operator unary_expr		{ $$ = append_to_list_node($1, $2); }
	;

multiplicative_expr
	: unary_expr							{ $$ = $1; }
	| multiplicative_expr '*' unary_expr	{ $$ = create_node(AST_MUL); $$->op = "*"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| multiplicative_expr '/' unary_expr	{ $$ = create_node(AST_DIV); $$->op = "/"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| multiplicative_expr '%' unary_expr	{ $$ = create_node(AST_REM); $$->op = "%"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

additive_expr
	: multiplicative_expr						{ $$ = $1; }
	| additive_expr '+' multiplicative_expr		{ $$ = create_node(AST_ADD); $$->op = "+"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| additive_expr '-' multiplicative_expr		{ $$ = create_node(AST_SUB); $$->op = "-"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

relational_expr
	: additive_expr							{ $$ = $1; }
	| relational_expr '<' additive_expr		{ $$ = create_node(AST_L); $$->op = "<"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr '>' additive_expr		{ $$ = create_node(AST_G); $$->op = ">"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr LE_OP additive_expr	{ $$ = create_node(AST_LE); $$->op = "<="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| relational_expr GE_OP additive_expr	{ $$ = create_node(AST_GE); $$->op = ">="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

equality_expr
	: relational_expr						{ $$ = $1; }
	| equality_expr EQ_OP relational_expr	{ $$ = create_node(AST_EQ); $$->op = "=="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| equality_expr NE_OP relational_expr	{ $$ = create_node(AST_NE); $$->op = "!="; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

logical_and_expr
	: equality_expr								{ $$ = $1; }
	| logical_and_expr AND_OP equality_expr		{ $$ = create_node(AST_AND); $$->op = "&&"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

logical_or_expr
	: logical_and_expr							{ $$ = $1; }
	| logical_or_expr OR_OP logical_and_expr	{ $$ = create_node(AST_OR); $$->op = "||"; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

assignment_expr
	: logical_or_expr									{ $$ = $1; }
	| postfix_expr assignment_operator assignment_expr	{ $$ = $2; append_to_list_node($$, $1); append_to_list_node($$, $3); }
	;

assignment_operator
	: '='			{ $$ = create_node(AST_ASSIG_EQUAL); $$->op = "="; }
	;

unary_operator
	: UMINUS		{ $$ = create_node(AST_UMINUS); $$->op = "neg"; }
	;

literal
	: BOOL_VAL				{ $$ = create_dec_node($1, AST_BOOL); }
	| STRING_VAL			{ $$ = create_string_node($1); }
	| CHAR_VAL				{ $$ = create_char_node($1); }
	| HEX_VAL				{ $$ = create_dec_node($1, AST_HEX); }
	| BITS_VAL				{ $$ = create_dec_node($1, AST_BIT); }
	| DEC_VAL				{ $$ = create_dec_node($1, AST_NUM); }
	;

func_signature
	: identifier '(' arg_def_list ')'				{ $$ = create_node(AST_FUNC_SIGNATURE); append_to_list_node($$, $1); append_to_list_node($$, $3); }
	| identifier EMPTY_BRACKETS						{ $$ = create_node(AST_FUNC_SIGNATURE); append_to_list_node($$, $1); }
	| identifier '(' arg_def_list ')' OF type_ref	{ $$ = create_node(AST_FUNC_SIGNATURE); append_to_list_node($$, $1); append_to_list_node($$, $3); append_to_list_node($$, $6); }	
	| identifier EMPTY_BRACKETS OF type_ref			{ $$ = create_node(AST_FUNC_SIGNATURE); append_to_list_node($$, $1); append_to_list_node($$, $4); }
	;

arg_def_list
	: arg_def						{ $$ = create_list_node($1); }
	| arg_def_list ',' arg_def		{ $$ = append_to_list_node($1, $3); }
	;

arg_def
	: identifier					{ $$ = create_arg_def_node($1, NULL); }
	| identifier OF type_ref		{ $$ = create_arg_def_node($1, $3); }
	;

type_ref
	: builtin				{ $$ = create_type_ref_node($1); }
	| identifier			{ $$ = create_type_ref_node($1); }
	| array					{ $$ = create_type_ref_node($1); }
	;

array
	: builtin ARRAY '[' DEC_VAL ']'		{ $$ = create_node(AST_TYPE_ARRAY); append_to_list_node($$, $1); append_to_list_node($$, create_dec_node($4, AST_NUM));}
	| identifier ARRAY '[' DEC_VAL ']'	{ $$ = create_node(AST_TYPE_ARRAY); append_to_list_node($$, $1); append_to_list_node($$, create_dec_node($4, AST_NUM));}
	;

builtin
	: BOOL			{ $$ = create_type_x_node($1, AST_TYPE_BOOL); }
	| BYTE			{ $$ = create_type_x_node($1, AST_TYPE_BYTE); }
	| INT			{ $$ = create_type_x_node($1, AST_TYPE_INT); }
	| UINT			{ $$ = create_type_x_node($1, AST_TYPE_UINT); }
	| LONG			{ $$ = create_type_x_node($1, AST_TYPE_LONG); }
	| ULONG			{ $$ = create_type_x_node($1, AST_TYPE_ULONG); }
	| CHAR			{ $$ = create_type_x_node($1, AST_TYPE_CHAR); }
	| STRING		{ $$ = create_type_x_node($1, AST_TYPE_STRING); }
	;

identifier
	: IDENTIFIER	{ $$ = create_id_node($1); }
	;

%%

int yyerror(const char *s) {
    /* yylloc is available because of %locations */
    fprintf(stderr, "Syntax error at %d:%d — %s\n",
            yylloc.first_line, yylloc.first_column, s);
    return 0;
}
