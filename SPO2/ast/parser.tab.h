/* A Bison parser, made by GNU Bison 2.3.  */

/* Skeleton interface for Bison GLR parsers in C

   Copyright (C) 2002, 2003, 2004, 2005, 2006 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.  */

/* As a special exception, you may create a larger work that contains
   part or all of the Bison parser skeleton and distribute that work
   under terms of your choice, so long as that work isn't itself a
   parser generator using the skeleton or a modified version thereof
   as a parser skeleton.  Alternatively, if you modify or redistribute
   the parser skeleton itself, you may (at your option) remove this
   special exception, which will cause the skeleton and the resulting
   Bison output files to be licensed under the GNU General Public
   License without this special exception.

   This special exception was added by the Free Software Foundation in
   version 2.2 of Bison.  */

/* Tokens.  */
#ifndef YYTOKENTYPE
# define YYTOKENTYPE
   /* Put the tokens into the symbol table, so that GDB and other debuggers
      know about them.  */
   enum yytokentype {
     OTHER = 258,
     IDENTIFIER = 259,
     EMPTY_BRACKETS = 260,
     ARRAY = 261,
     OF = 262,
     IF = 263,
     THEN = 264,
     ELSE = 265,
     BEGIN_T = 266,
     END = 267,
     WHILE = 268,
     UNTIL = 269,
     BREAK = 270,
     DEF = 271,
     AND_OP = 272,
     OR_OP = 273,
     LE_OP = 274,
     GE_OP = 275,
     EQ_OP = 276,
     NE_OP = 277,
     UMINUS = 278,
     BOOL_VAL = 279,
     STRING_VAL = 280,
     CHAR_VAL = 281,
     HEX_VAL = 282,
     BITS_VAL = 283,
     DEC_VAL = 284,
     BOOL = 285,
     BYTE = 286,
     INT = 287,
     UINT = 288,
     LONG = 289,
     ULONG = 290,
     CHAR = 291,
     STRING = 292,
     LOWER_THAN_ELSE = 293
   };
#endif


/* Copy the first part of user declarations.  */
#line 2 "./parser.y"

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



#if ! defined YYSTYPE && ! defined YYSTYPE_IS_DECLARED
typedef union YYSTYPE 
#line 48 "./parser.y"
{
	AST_Node *node;

	//uint32_t num_val;
	char *num_str;
	char *type_name;
	char *string_val;
	char char_val;

	char *id;

	char *brackets;
}
/* Line 2616 of glr.c.  */
#line 121 "parser.tab.h"
	YYSTYPE;
# define YYSTYPE_IS_DECLARED 1
# define YYSTYPE_IS_TRIVIAL 1
#endif

#if ! defined YYLTYPE && ! defined YYLTYPE_IS_DECLARED
typedef struct YYLTYPE
{

  int first_line;
  int first_column;
  int last_line;
  int last_column;

} YYLTYPE;
# define YYLTYPE_IS_DECLARED 1
# define YYLTYPE_IS_TRIVIAL 1
#endif


extern YYSTYPE yylval;

extern YYLTYPE yylloc;


