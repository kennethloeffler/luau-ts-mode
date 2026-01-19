;;; luau-ts-mode.el --- Major mode for editing Luau files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Kenneth Loeffler

;; Author: Kenneth Loeffler <kenloef@gmail.com>
;; Version: 0.0.0
;; Keywords: luau, languages
;; URL: https://github.com/kennethloeffler/luau-ts-mode

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This package provides `luau-ts-mode' for editing Luau files, which
;; uses Tree Sitter to parse the language..
;;
;; This package is compatible with the Tree Sitter grammar for Luau
;; found at https://github.com/4teapo/tree-sitter-luau.

;;; Code:

(require 'treesit)

(eval-when-compile
  (require 'rx))

(add-to-list
 'treesit-language-source-alist
 '(luau "https://github.com/4teapo/tree-sitter-luau"
       :commit "0d66daa8a247fad86c19964dd2406a8646cac966")
 t)

(defgroup luau-ts nil
  "Major mode for editing Luau files."
  :prefix "luau-ts-"
  :group 'languages)

(defcustom luau-ts-indent-offset 4
  "Spaces (or tab width if `indent-tabs-mode' enabled) for indentation."
  :type 'natnum
  :safe 'natnump)

(defvar luau-ts--builtin-fns
  '("require" "assert" "error" "gcinfo" "getfenv" "getmetatable" "next"
    "newproxy" "print" "rawequal" "rawget" "select" "setfenv" "setmetatable"
    "tonumber" "tostring" "type" "typeof" "ipairs" "pairs" "pcall" "xpcall" "unpack"))

(defvar luau-ts--builtin-metamethods
  '("__index" "__newindex" "__call" "__concat" "__unm" "__add" "__sub" "__mul"
    "__div" "__idiv" "__mod" "__pow" "__tostring" "__metatable" "__eq" "__lt"
    "__le" "__mode" "__gc" "__len" "__iter"))

(defvar luau-ts--stdlib
  '("math" "table" "string" "coroutine" "bit32" "utf8" "os" "debug"
    "buffer" "vector"))

(defvar luau-ts--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?+  "."    table)
    (modify-syntax-entry ?-  ". 12" table)
    (modify-syntax-entry ?=  "."    table)
    (modify-syntax-entry ?%  "."    table)
    (modify-syntax-entry ?^  "."    table)
    (modify-syntax-entry ?~  "."    table)
    (modify-syntax-entry ?<  "."    table)
    (modify-syntax-entry ?>  "."    table)
    (modify-syntax-entry ?/  "."    table)
    (modify-syntax-entry ?*  "."    table)
    (modify-syntax-entry ?\n ">"    table)
    (modify-syntax-entry ?\' "\""   table)
    (modify-syntax-entry ?\" "\""   table)
    table)
  "Syntax table for `luau-ts-mode'.")

(defvar luau-ts--font-lock-rules
  (treesit-font-lock-rules
   :language 'luau
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'luau
   :feature 'definition
   '((local_function_declaration name: (identifier) @font-lock-function-name-face)
     (function_declaration
      name: [(identifier) @font-lock-function-name-face
             (dot_index_expression field: (field_identifier) @font-lock-function-name-face)
             (method_index_expression method: (field_identifier) @font-lock-function-name-face)]))

   :language 'luau
   :feature 'keyword
   `((["local" "while" "repeat" "until" "for" "in" "if" "or" "and"
       "elseif" "else" "then" "do" "function" "end" "return" "not"
       (break_statement) (continue_statement)]
      @font-lock-keyword-face)
     (type_alias_declaration ["export" "type"] @font-lock-keyword-face)
     (type_function_declaration ["export" "type"] @font-lock-keyword-face)
     (declare_global_declaration "declare" @font-lock-keyword-face)
     (declare_global_function_declaration "declare" @font-lock-keyword-face)
     (declare_class_declaration ["declare" "class" "extends"] @font-lock-keyword-face)
     (declare_extern_type_declaration ["declare" "extern" "type"
                                       "extends" "with"]
                                      @font-lock-keyword-face))

   :language 'luau
   :feature 'string
   '(((string) @font-lock-string-face)
     ((interpolated_string [content: (string_content) "`"] @font-lock-string-face))
     (string_interpolation ["{" "}"] @font-lock-string-face))

   :language 'luau
   :feature 'binding
   '((binding name: (identifier) @font-lock-variable-name-face))

   :language 'luau
   :feature 'builtin
   `((function_call name: [(identifier) @font-lock-builtin-face
                           (parenthesized_expression (identifier) @font-lock-builtin-face)]
                    (:match ,(regexp-opt luau-ts--builtin-fns 'symbols)
                            @font-lock-builtin-face))
     (function_call name: [(dot_index_expression field: (field_identifier) @font-lock-builtin-face)
                           (method_index_expression method: (field_identifier) @font-lock-builtin-face)]
                    (:match ,(regexp-opt luau-ts--builtin-metamethods 'symbols)
                            @font-lock-builtin-face))
     ((dot_index_expression table: (identifier) @library
                            field: (field_identifier) @font-lock-builtin-face)
                    (:match ,(regexp-opt luau-ts--stdlib 'symbols) @library))
     ((identifier) @font-lock-builtin-face (:match ,(regexp-opt luau-ts--stdlib 'symbols)
                                                   @font-lock-builtin-face))
     ((identifier) @font-lock-builtin-face (:equal @font-lock-builtin-face "self"))
     (typeof_type "typeof" @font-lock-builtin-face))

   :language 'luau
   :feature 'constant
   '(([(nil) (false) (true)] @font-lock-constant-face))

   :language 'luau
   :feature 'number
   '((number) @font-lock-number-face)

   :language 'luau
   :feature 'type
   '(((type_identifier) @font-lock-type-face))

   :language 'luau
   :feature 'attribute
   '(((table_property_attribute) @font-lock-preprocessor-face)
	 ((parameter_attribute name: (identifier) @font-lock-preprocessor-face))
     ((attribute ["@" @font-lock-preprocessor-face name: (identifier) @font-lock-preprocessor-face]))
     ((hash_bang_line) @font-lock-preprocessor-face)))
  "Tree-sitter font-lock settings for `luau-ts-mode'.")


(defvar luau-ts--indent-rules
  `((luau
     ((parent-is "chunk") column-0 0)
     ((node-is "end") parent-bol 0)
     ((node-is "until") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is ">") parent-bol 0)
     ((and (node-is "then") (parent-is "if_statement")) parent-bol 0)
     ((and (node-is "else") (parent-is "if_statement")) parent-bol 0)
     ((and (node-is "elseif") (parent-is "if_statement")) parent-bol 0)
     ((parent-is "block") parent-bol 0)
     ((parent-is "table_property_list") parent-bol 0)
     ((parent-is "type_union") parent-bol luau-ts-indent-offset)
     ((parent-is "type_intersection") parent-bol luau-ts-indent-offset)
     ((parent-is "binary_expression") parent-bol luau-ts-indent-offset)
     ((parent-is "expression_list") standalone-parent luau-ts-indent-offset)
     ((parent-is "table_property") parent-bol luau-ts-indent-offset)
     ((parent-is "function_type") parent-bol luau-ts-indent-offset)
     ((parent-is "bound_type_list") parent-bol 0)
     ((parent-is "parenthesized_expression") parent-bol luau-ts-indent-offset)
     ((parent-is "declaration") parent-bol luau-ts-indent-offset)
     ((parent-is "function_definition") parent-bol luau-ts-indent-offset)
     ((parent-is "if_else_expression") parent-bol luau-ts-indent-offset)
     ((parent-is "type_parameters") parent-bol 0)
     ((parent-is "parameters") parent-bol luau-ts-indent-offset)
     ((parent-is "type_reference") parent-bol luau-ts-indent-offset)
     ((parent-is "arguments") parent-bol luau-ts-indent-offset)
     ((node-is "binary_expression") parent-bol luau-ts-indent-offset)
     ((parent-is "do_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "else_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "if_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "while_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "repeat_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "for_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "return_statement") parent-bol luau-ts-indent-offset)
     ((parent-is "table_constructor") parent-bol luau-ts-indent-offset)
     ((parent-is "table_type") parent-bol luau-ts-indent-offset)))
  "Tree-sitter indent rules for `luau-ts-mode'.")


(defun luau-ts--syntax-propertize (beg end)
  "Edit the text properties between BEG and END to handle paired < and >.

Sometimes < and > are punctuation, other times they're pairs."
  (goto-char beg)
  (while (re-search-forward (rx (or "<" ">")) end t)
    (when (not (string-equal (treesit-node-type (treesit-node-at (match-beginning 0))) "->"))
     (pcase (treesit-node-type
            (treesit-node-parent
             (treesit-node-at (match-beginning 0))))
      ((or "type_reference" "type_alias_declaration" "function_type" "function_definition")
       (put-text-property (match-beginning 0)
                          (match-end 0)
                          'syntax-table
                          (pcase (char-before)
                            (?< '(4 . ?>))
                            (?> '(5 . ?<)))))))))

;;;###autoload
(define-derived-mode luau-ts-mode prog-mode "Luau"
  "Major mode for editing Luau files, powered by tree-sitter."
  :group 'luau
  :syntax-table luau-ts--syntax-table

  (when (treesit-ensure-installed 'luau)
    (setq treesit-primary-parser (treesit-parser-create 'luau))

    (setq-local syntax-propertize-function
                #'luau-ts--syntax-propertize)

    (setq-local treesit-font-lock-settings luau-ts--font-lock-rules)
    (setq-local treesit-font-lock-feature-list
                '((comment definition)
                  (keyword string)
                  (binding builtin constant number type attribute)))

    (setq-local comment-start "--")
    (setq-local comment-end "")
    (setq-local comment-start-skip (rx "--" (* (syntax whitespace))))

    (setq-local treesit-simple-indent-rules luau-ts--indent-rules)
    (setq-local tab-width luau-ts-indent-offset)

    (treesit-major-mode-setup)))

(provide 'luau-ts-mode)

;;; luau-ts-mode.el ends here
