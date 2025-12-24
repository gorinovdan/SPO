%option yylineno

%{
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <inttypes.h>
#include "ast.h"
#include "parser.tab.h"

extern YYLTYPE yylloc;  /* Bison location for current token */
int yycolumn = 1;       /* column number (1-based) */

/* helper to fill yylloc and advance column */
#define SET_YYLOC do {                       \
    yylloc.first_line   = yylineno;          \
    yylloc.first_column = yycolumn;          \
    yylloc.last_line    = yylineno;          \
    yylloc.last_column  = yycolumn + yyleng - 1; \
    yycolumn += yyleng;                      \
} while(0)

void showError();
void read_type();
void read_string();
void read_num_str();
void read_id();
void read_brackets();
%}

comment				"//"[^\n]*
empty_brackets		\(\)

identifier			[a-zA-Z_][a-zA-Z_0-9]*
string				\"(\\.|[^\\"\n])*\"
number				[0-9]+
boolean				true|false
character			'[^']'
bit					0[bB][01]+
hex					0[xX][0-9A-Fa-f]+
tabulation			[ \t\v\f\r]
newline             [\n]

%%
{comment}			{ }

{empty_brackets}	{ SET_YYLOC; read_brackets(); return(EMPTY_BRACKETS); }

"neg"				{ SET_YYLOC; return(UMINUS); }
"def"				{ SET_YYLOC; return(DEF); }

"bool"				{ SET_YYLOC; read_type(); return(BOOL); }
"byte"				{ SET_YYLOC; read_type(); return(BYTE); }
"int"				{ SET_YYLOC; read_type(); return(INT); }
"uint"				{ SET_YYLOC; read_type(); return(UINT); }
"long"				{ SET_YYLOC; read_type(); return(LONG); }
"ulong"				{ SET_YYLOC; read_type(); return(ULONG); }
"char"				{ SET_YYLOC; read_type(); return(CHAR); }
"string"			{ SET_YYLOC; read_type(); return(STRING); }

"array"				{ SET_YYLOC; return(ARRAY); }

"of"				{ SET_YYLOC; return(OF); }

"if"				{ SET_YYLOC; return(IF); }
"then"				{ SET_YYLOC; return(THEN); }
"else"				{ SET_YYLOC; return(ELSE); }

"begin"				{ SET_YYLOC; return(BEGIN_T); }
"end"				{ SET_YYLOC; return(END); }
"while"				{ SET_YYLOC; return(WHILE); }
"until"				{ SET_YYLOC; return(UNTIL); }
"break"				{ SET_YYLOC; return(BREAK); }


{boolean}			{ SET_YYLOC; read_num_str(); return(BOOL_VAL); }
{identifier}		{ SET_YYLOC; read_id(); return(IDENTIFIER); }

{string}			{ SET_YYLOC; read_string(); return(STRING_VAL); }
{character}			{ SET_YYLOC; yylval.char_val = yytext[1]; return(CHAR_VAL); }
{hex}				{ SET_YYLOC; read_num_str(); return(HEX_VAL); }
{bit}				{ SET_YYLOC; read_num_str(); return(BITS_VAL); }
{number}			{ SET_YYLOC; read_num_str(); return(DEC_VAL); }

"&&"			{ SET_YYLOC; return(AND_OP); }
"||"			{ SET_YYLOC; return(OR_OP); }
"<="			{ SET_YYLOC; return(LE_OP); }
">="			{ SET_YYLOC; return(GE_OP); }
"=="			{ SET_YYLOC; return(EQ_OP); }
"!="			{ SET_YYLOC; return(NE_OP); }

","					{ SET_YYLOC; return(','); }
"."					{ SET_YYLOC; return('.'); }
"("					{ SET_YYLOC; return('('); }
")"					{ SET_YYLOC; return(')'); }
"["					{ SET_YYLOC; return('['); }
"]"					{ SET_YYLOC; return(']'); }
"{"					{ SET_YYLOC; return('{'); }
"}"					{ SET_YYLOC; return('}'); }
";"					{ SET_YYLOC; return(';'); }

">"					{ SET_YYLOC; return('>'); }
"<"					{ SET_YYLOC; return('<'); }
"="					{ SET_YYLOC; return('='); }
"!"					{ SET_YYLOC; return('!'); }

"+"					{ SET_YYLOC; return('+'); }
"-"					{ SET_YYLOC; return('-'); }

"*"					{ SET_YYLOC; return('*'); }
"%"					{ SET_YYLOC; return('%'); }
"/"					{ SET_YYLOC; return('/'); }

{newline}           { yycolumn = 1; /* newline — reset column */ }

{tabulation}		{ yycolumn += yyleng; /* spaces update column only */ }
.					{ SET_YYLOC; showError(); return(OTHER);}

%%

void read_brackets() {
	yylval.brackets = malloc(yyleng + 1);
	snprintf(yylval.brackets, yyleng + 1, "%s", yytext);
	//sscanf(yytext, "%s", yylval.brackets);
}

//void read_bool() {
//	if (strcmp(yytext, "true") == 0) {
//		yylval.num_val = 1;
//	} else {
//		yylval.num_val = 0;
//	}
//
//	strtoul(yytext, NULL, 16); return(HEX_VAL);
//  strtoul(yytext + 2, NULL, 2); return(BITS_VAL);
//  strtoul(yytext, NULL, 10); return(DEC_VAL);
//}

void read_num_str() {
	yylval.num_str = malloc(yyleng + 1);
	snprintf(yylval.num_str, yyleng + 1, "%s", yytext);
}

void read_type() {
	yylval.type_name = malloc(yyleng + 1);
	snprintf(yylval.type_name, yyleng + 1, "%s", yytext);
}

void read_id() {
	yylval.id = malloc(yyleng + 1);
	snprintf(yylval.id, yyleng + 1, "%s", yytext);
	//sscanf(yytext, "%s", yylval.id);
}

void read_string() {
	int res_len = yyleng - 2 + 1;
	yylval.string_val = malloc(res_len);
	yytext[yyleng - 1] = '\0';
	snprintf(yylval.string_val, res_len, "%s", yytext + 1);
	//strncpy(yylval.string_val, yytext + 1, yyleng - 2);
}

void showError() {
    fprintf(stderr, "Lexical error at %d:%d — unexpected token '%s'\n", yylineno, yycolumn, yytext);
}

int yywrap(){
    return 1;
}
