;;; rexx-mode.el --- Major mode for Rexx language  -*- lexical-binding: t; -*-
;; Author: ChatGPT
;; Version: 0.2
;; Keywords: languages
;; Package-Requires: ((emacs "24.4"))
;; URL: https://example.invalid/rexx-mode

;;; Commentary:
;; Minimal Rexx major mode with:
;; - regexp-opt keyword highlighting
;; - built-in function highlighting
;; - label & number highlighting
;; - CMS Pipelines: pipes, stage labels, common stage names
;; - indentation for do/end, loop/end, select/when/otherwise/end
;; - small abbrev set
;;
;; Usage:
;;   (add-to-list 'load-path "/path/to/dir")
;;   (require 'rexx-mode)
;;   (add-to-list 'auto-mode-alist '("\\.rex\\'" . rexx-mode))
;;   (add-to-list 'auto-mode-alist '("\\.rexx\\'" . rexx-mode))
;;   (add-to-list 'auto-mode-alist '("\\.cmd\\'" . rexx-mode))

;;; Code:

(require 'cl-lib)

(defgroup rexx-mode nil
  "Major mode for editing Rexx."
  :group 'languages)

;; ------------------------------
;; Keyword sets
;; ------------------------------

(defconst rexx-keywords
  '("address" "arg" "break" "call" "do" "drop"
    "echo" "else" "end" "exit"
    "forever" "if" "interpret" "iterate" "leave"
    "nop" "numeric" "options" "otherwise"
    "parse" "procedure" "push" "pull"
    "queue" "return" "say" "select" "shell" "signal"
    "then" "to" "trace" "until" "upper" "when" "while" "loop")
  "Rexx keywords / statements. Case-insensitive.")

(defconst rexx-builtin-functions
  '("abbrev" "abs" "address" "arg" "center" "centre" "changestr" "compare"
    "copies" "c2d" "c2x" "d2c" "d2x" "datatype" "delstr" "delword"
    "errortext" "form" "format" "fuzz" "insert" "lastpos" "left"
    "length" "lower" "max" "min" "overlay" "pos" "reverse" "right"
    "sign" "space" "strip" "substr" "subword" "symbol" "translate"
    "trunc" "upper" "value" "verify" "word" "wordindex" "wordlength"
    "wordpos" "words" "xrange" "xranges")
  "Common Rexx built-in functions (portable subset).")

(defconst rexx-keywords-regexp
  (concat "\\<" (regexp-opt rexx-keywords t) "\\>")
  "Optimized regexp for Rexx keywords.")

(defconst rexx-builtin-regexp
  (concat "\\<" (regexp-opt rexx-builtin-functions t) "\\>")
  "Optimized regexp for Rexx built-in functions.")

;; ------------------------------
;; Pipelines (CMS Pipelines style)
;; ------------------------------

;; Match one or two pipes: | or ||
(defconst rexx-pipe-operator-regexp
  "[|][|]?"
  "Matches Rexx/CMS pipeline operator (single or double pipe).")

;; Match a stage label immediately after a pipe:  | stage:
(defconst rexx-pipe-stage-label-regexp
  "[|][ \t]*\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*:"
  "Label used as a pipeline stage after a pipe.")

;; Common CMS Pipelines stage names (extend as needed)
(defconst rexx-pipe-stage-names
  '("specs" "locate" "change" "find" "take" "drop" "sort" "append" "console"
    "stem" "literal" "split" "join" "rexx" "host" "command" "substitute"
    "strip" "center" "lower" "upper" "count" "unique" "merge" "tee" "out" "in"
    "fields" "blank" "nonblank" "trim" "pack" "unpack" "pad" "date" "time")
  "A non-exhaustive list of common CMS Pipelines stages.")

(defconst rexx-pipe-stage-name-regexp
  (concat "[|][ \t]*" (regexp-opt rexx-pipe-stage-names t) "\\_>")
  "Matches a known pipeline stage name immediately after a pipe.")

;; ------------------------------
;; Syntax table
;; ------------------------------

(defvar rexx-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; Comment syntax: /* ... */
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23"   st)
    (modify-syntax-entry ?\n "> b"   st)
    (modify-syntax-entry ?# "< b" st)   ;; '#' starts a comment
    ;; Strings: both ' and "
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?'  "\"" st)

    ;; Word constituents: underscore
    (modify-syntax-entry ?_  "w" st)

    st)
  "Syntax table for `rexx-mode'.")


;; After defining the syntax table:
(defun rexx-syntax-propertize (start end)
  (funcall
   (syntax-propertize-rules
    ("\\(--\\)\\(?:\\s-\\|$\\)" (1 "< b"))) ; '--' starts a comment
   start end))

;; ------------------------------
;; Font-lock
;; ------------------------------

(defconst rexx-label-regexp
  "^[ \t]*\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*:"
  "Rexx label at beginning of line.")

(defconst rexx-number-regexp
  "\\b\\([0-9]+\\(?:\\.[0-9]+\\)?\\)\\b"
  "Numeric literals.")

(defvar rexx-font-lock-keywords
  `(
    ;; Pipeline operators and stage labels
    (,rexx-pipe-operator-regexp . font-lock-builtin-face)
    (,rexx-pipe-stage-label-regexp (1 font-lock-function-name-face))
    ;; Known pipeline stage names after a pipe
    (,rexx-pipe-stage-name-regexp (1 font-lock-keyword-face))

    ;; Core Rexx highlighting
    (,rexx-keywords-regexp . font-lock-keyword-face)
    (,rexx-builtin-regexp  . font-lock-builtin-face)
    (,rexx-label-regexp    (1 font-lock-function-name-face))
    (,rexx-number-regexp   (1 font-lock-constant-face))
   )
  "Default expressions to highlight in Rexx mode.")

;; Custom comment face:
(defface rexx-comment-face
  '((((class color)) :foreground "SeaGreen3")
    (t :inherit font-lock-comment-face))
  "Face for Rexx comments.")
(setq-local rexx--comment-face-cookie
            (face-remap-add-relative 'font-lock-comment-face 'rexx-comment-face))

;; ------------------------------
;; Indentation
;; ------------------------------

(defgroup rexx-indent nil
  "Indentation settings for Rexx mode."
  :group 'rexx-mode)

(defcustom rexx-indent-offset 2
  "Indentation offset for Rexx blocks."
  :type 'integer
  :group 'rexx-indent)

(defun rexx--line-matches-p (regex)
  "Return non-nil if current line matches REGEX."
  (save-excursion
    (beginning-of-line)
    (looking-at regex)))

(defun rexx--previous-code-line-indent ()
  "Return indentation of the previous non-blank, non-comment line."
  (save-excursion
    (let ((found nil) (indent 0))
      (while (and (not found)
                  (zerop (forward-line -1)))
        (cond
         ;; skip blank lines
         ((looking-at "^[ \t]*$"))
         ;; skip comment-only lines
         ((looking-at "^[ \t]*/\\*")
          ;; if we're inside a block comment, skip until its start
          (while (and (not (bobp))
                      (not (looking-at ".*\\*/")))
            (forward-line -1))
          (forward-line -1))  ;; step above the */ line
         (t (setq found t
                  indent (current-indentation)))))
      indent)))

(defun rexx--previous-code-line-text ()
  "Return text of the previous non-blank, non-comment line (trimmed)."
  (save-excursion
    (let ((text ""))
      (while (and (zerop (forward-line -1))
                  (or (looking-at "^[ \t]*$")
                      (looking-at "^[ \t]*/\\*"))))
      (setq text (buffer-substring-no-properties
                  (line-beginning-position) (line-end-position)))
      (string-trim text))))

(defconst rexx--block-openers
  '("do" "loop" "select")
  "Keywords that increase indentation for the following line.")

(defconst rexx--mid-block
  '("when" "otherwise")
  "Keywords that should outdent to the enclosing SELECT level.")

(defconst rexx--block-closers
  '("end")
  "Keywords that close a block and should outdent.")

(defun rexx--prev-line-opens-block-p ()
  "Return non-nil if previous code line opens a block."
  (let* ((line (downcase (rexx--previous-code-line-text))))
    (or (string-match-p "\\_<\\(do\\|loop\\|select\\)\\_>" line)
        (string-match-p "\\_<then\\_>" line)
        (string-match-p "^\\s-*else\\_>" line))))

(defun rexx--current-line-closer-or-mid-p ()
  "Return 'close for END, 'mid for WHEN/OTHERWISE, or nil."
  (save-excursion
    (beginning-of-line)
    (let ((case-fold-search t))
      (cond
       ((looking-at "\\s-*\\_<end\\_>") 'close)
       ((looking-at "\\s-*\\_<\\(when\\|otherwise\\)\\_>") 'mid)
       (t nil)))))

(defun rexx-calculate-indentation ()
  "Compute desired indentation for the current line."
  (save-excursion
    (let* ((case-fold-search t)
           (prev-indent (rexx--previous-code-line-indent))
           (kind (rexx--current-line-closer-or-mid-p))
           (indent prev-indent))
      (pcase kind
        ('close (setq indent (max 0 (- prev-indent rexx-indent-offset))))
        ('mid   (setq indent (max 0 (- prev-indent rexx-indent-offset))))
        (_      (when (rexx--prev-line-opens-block-p)
                  (setq indent (+ prev-indent rexx-indent-offset)))))
      (max 0 indent))))

(defun rexx-indent-line ()
  "Indent current line according to Rexx rules."
  (interactive)
  (let ((col (current-column)))
    (indent-line-to (rexx-calculate-indentation))
    (when (> col (current-column))
      (move-to-column col))))

;; ------------------------------
;; Abbreviations
;; ------------------------------

(defgroup rexx-abbrev nil
  "Abbreviations for Rexx mode."
  :group 'rexx-mode)

(defcustom rexx-use-default-abbrevs t
  "If non-nil, enable a small default abbrev set for Rexx."
  :type 'boolean
  :group 'rexx-abbrev)

(define-abbrev-table 'rexx-mode-abbrev-table
  '(("ii"      "interpret" nil :system t)
    ("sel"     "select"    nil :system t)
    ("wh"      "when"      nil :system t)
    ("oth"     "otherwise" nil :system t)
    ("proc"    "procedure" nil :system t)
    ("num"     "numeric"   nil :system t)
    ("ret"     "return"    nil :system t)
    ("sig"     "signal"    nil :system t)
    ("th"      "then"      nil :system t)
    ("uq"      "upper"     nil :system t)
    ("qq"      "queue"     nil :system t)))

(defun rexx--maybe-enable-abbrevs ()
  "Enable `abbrev-mode' if `rexx-use-default-abbrevs' is non-nil."
  (when rexx-use-default-abbrevs
    (abbrev-mode 1)))

;; ------------------------------
;; Mode definition
;; ------------------------------

;;;###autoload
(define-derived-mode rexx-mode prog-mode "Rexx"
  "Major mode for editing Rexx code."
  :syntax-table rexx-mode-syntax-table
  (setq-local comment-start "/* ")
  (setq-local comment-end " */")

  (setq rexx-font-lock-keywords-2
  (append
    rexx-font-lock-keywords
    (list
      ;; ports
      (list
	"address *\\(\\<\\w*\\>\\)" '(1 font-lock-variable-name-face nil))
      ;; user function names
      (list
	"^\\(\\<.*\\>\\):" '(1 font-lock-type-face nil))
      )
    
    )
  )
  (setq-local font-lock-defaults '(rexx-font-lock-keywords-2))
  (setq-local font-lock-keywords-case-fold-search t)  ;; case-insensitive
  (setq-local indent-line-function #'rexx-indent-line)
  (setq-local local-abbrev-table rexx-mode-abbrev-table)
  (setq-local syntax-propertize-function #'rexx-syntax-propertize)
  (setq-local comment-start "-- ")
  (setq-local comment-start-skip "\\(?:--\\|#\\)\\s-*")
  (setq-local imenu-generic-expression `(("Labels" ,rexx-label-regexp 1)))
  ;; (rexx--maybe-enable-abbrevs)
  ;; Strings in both ' and "
  (modify-syntax-entry ?\" "\"" rexx-mode-syntax-table)
  (modify-syntax-entry ?'  "\"" rexx-mode-syntax-table))


;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rex\\'" . rexx-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.rexx\\'" . rexx-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.cmd\\'" . rexx-mode))

(provide 'rexx-mode)
;;; rexx-mode.el ends here
