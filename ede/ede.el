;;; ede.el --- Emacs Development Environment gloss

;;;  Copyright (C) 1998, 99  Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Version: 0.0.2
;; Keywords: project, make
;; RCS: $Id: ede.el,v 1.4 1999-01-21 21:29:25 zappo Exp $

;; This file is NOT part of GNU Emacs.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;; 
;; EDE is the top level Lisp interface to a project management scheme
;; for Emacs.  Emacs does many things well, including editing,
;; building, and debugging.  Folks migrating from other IDEs don't
;; seem to thing this qualifies, however, because they still have to
;; write the makefiles, and specify parameters to programs.
;;
;; This EDE mode will attempt to link these diverse programs together
;; into a comprehensive single interface, instead of a bunch of
;; different ones.

;;; Install
;;
;;  Place these files in your load path, and byte compile them
;;
;;  ede and it's support files depend on:
;;   eieio and make-mode.  It will use compile, gud, and speedbar.
;;
;;  This command enables project mode on all files.
;;
;;  (global-ede-mode t)

;;; Code:
(defvar ede-version "0.0"
  "Current version of the Emacs EDE.")

;; From custom web page for compatibility between versions of custom
(eval-and-compile
  (condition-case ()
      (require 'custom)
    (error nil))
  (if (and (featurep 'custom) (fboundp 'custom-declare-variable)
	   ;; Some XEmacsen w/ custom don't have :set keyword.
	   ;; This protects them against custom.
	   (fboundp 'custom-initialize-set))
      nil ;; We've got what we needed
    ;; We have the old custom-library, hack around it!
    (if (boundp 'defgroup)
	nil
      (defmacro defgroup (&rest args)
	nil))
    (if (boundp 'defcustom)
	nil
      (defmacro defcustom (var value doc &rest args)
	(` (defvar (, var) (, value) (, doc)))))))

(defgroup ede nil
  "Emacs Development Environment gloss."
  :group 'tools
  :group 'convenience
;  :version "20.3"
  )

(require 'eieio)

;;; Top level classes for projects and targets
;;
(defclass ede-project-autoload ()
  ((name :initarg :name :docstring "Name of this project type")
   (file :initarg :file :docstring "The lisp file belonging to this class.")
   (proj-file :initarg :proj-file 
	      :docstring "Name of a project file of this type.")
   (load-type :initarg :load-type
	      :docstring "Fn symbol used to load this project file.")
   (class-sym :initarg :class-sym
	      :docstring "Symbol representing the project class to use."))
  "Class representing minimal knowledge set to run preliminary EDE functions.
When more advanced functionality is needed from a project type, that projects
type is required and the load function used.")

(defvar ede-project-class-files
  (list
   (ede-project-autoload "edeproject"
			 :name "edeproject" :file 'ede-proj
			 :proj-file "Project.ede"
			 :load-type 'ede-proj-load
			 :class-sym 'ede-proj-project)
   (ede-project-autoload "automake"
			 :name "automake" :file 'project-am
			 :proj-file "Makefile.am"
			 :load-type 'project-am-load
			 :class-sym 'project-am-makefile)
   )
  "List of vectos defining how to determine what type of projects exist.")

;;; Generic project information manager objects
;;
(defclass ede-target ()
  ((name :initarg :name
	 :custom string
	 :docstring "Name of this target.")
   (path :initarg :path
	 :custom string
	 :docstring "The path to this target.")
   (takes-compile-command
    :initarg :takes-compile-command
    :initform nil
    :docstring "Non-nil if this target requires a user approved command."
    :allocation :class)
   (source :initarg :source
	   :custom (repeat object)
	   :documentation "Source files in this target.")   )
  "A top level target to build.")

(defclass ede-project ()
  ((name :initarg :name
	 :initform "Untitled"
	 :custom string
	 :docstring "The name used when generating distribution files.")
   (version :initarg :version
	    :initform "1.0"
	    :custom string
	    :docstring "The version number used when distributing files.")
   (file :initarg :file
	 :docstring "File name where this project is stored.")
   (root :initarg :root
	 :docstring "The root project file")
   (targets :initarg :targets
	    :custom (repeat object)
	    :docstring "List of top level targets in this project.")
   (subproj :initarg :subproj
	    :custom (repeat object)
	    :docstring "Sub projects controlled by this project.")
   )
  "Top level EDE project specification.
All specific project types must derive from this project.")

;;; Management variables
;;
(defvar ede-projects nil
  "A list of all active projects currently loaded in Emacs.")

(defvar ede-object nil
  "The current buffer's target object.
This object's class determines how to compile and debug from a buffer.")
(make-variable-buffer-local 'ede-object)

(defvar ede-constructing nil
  "Non nil when constructing a project hierarchy.")

(defvar ede-deep-rescan nil
  "Non nil means scan down a tree, otherwise rescans are top level only.
Do not set this to non-nil globally.  It is used internally.")

;;; Important macros for doing commands.
;;
(defmacro ede-with-projectfile (obj &rest forms)
  "For the project in which OBJ resides, execute FORMS."
  (list 'save-window-excursion
	(list 'let* (list
		     (list 'pf
			   (list 'if (list 'obj-of-class-p
					   obj 'ede-target)
				 (list 'ede-load-project-file
				       (list 'oref obj :path))
				 obj))
		     '(dbka (get-file-buffer (oref pf :file))))
	      '(if (not dbka) (find-file (oref pf :file))
		 (switch-to-buffer dbka))
	      (cons 'progn forms)
	      '(if (not dbka) (kill-buffer (current-buffer))))))
(put 'ede-with-projectfile 'lisp-indent-function 1)

;;; Minor mode specification
;;
(defvar ede-minor-mode nil
  "Non-nil in `emacs-lisp-mode' for automatic documentation checking.")
(make-variable-buffer-local 'ede-minor-mode)

;; We don't want to waste space.  There is a menu after all.
(add-to-list 'minor-mode-alist '(ede-minor-mode ""))

(defvar ede-minor-keymap
  (let ((map (make-sparse-keymap))
	(pmap (make-sparse-keymap)))
    (define-key pmap "e" 'ede-edit-file-target)
    (define-key pmap "a" 'ede-add-file)
    (define-key pmap "d" 'ede-remove-file)
    (define-key pmap "t" 'ede-new-target)
    (define-key pmap "g" 'ede-rescan-toplevel)
    (define-key pmap "s" 'ede-speedbar)
    (define-key pmap "l" 'ede-load-project-file)
    (define-key pmap "C" 'ede-compile-project)
    (define-key pmap "c" 'ede-compile-target)
    (define-key pmap "d" 'ede-debug-target)
    ;; bind our submap into map
    (define-key map "\C-c." pmap)
    map)
  "Keymap used in project minor mode.")

(if ede-minor-keymap
    (easy-menu-define
     ede-minor-menu ede-minor-keymap "Project Minor Mode Menu"
     '("Project"
       [ "Create a new project" ede-new (not ede-object) ]
       [ "Load a project" ede t ]
       [ "Rescan Project Files" ede-rescan-toplevel t ]
       [ "Customize Project" ede-customize (ede-current-project) ]
       "---"
       [ "Create New Target" ede-new-target (ede-current-project) ]
       [ "Delete Target" ede-delete-target ede-object ]
       [ "Add to Target" ede-add-file (ede-current-project) ]
       [ "Modify Target" ede-edit-file-target
	 (and ede-object
	      (not (obj-of-class-p ede-object ede-project))) ]
       [ "Remove from Target" ede-remove-file
	 (and ede-object
	      (not (obj-of-class-p ede-object ede-project))) ]
       "---"
       [ "Compile project" ede-compile-project t ]
       [ "Compile target" ede-compile-target t ]
       [ "Debug target" ede-debug-target
	 (and ede-object
	      (obj-of-class-p ede-object ede-target)) ]
       [ "Make distribution" ede-make-dist t ]
       "---"
       [ "Speedbar" speedbar t ]
       [ "Speedbar Project" ede-speedbar t ]
       )))

;; Allow re-insertion of a new keymap
(let ((a (assoc 'ede-minor-mode minor-mode-map-alist)))
  (if a
      (setcdr a ede-minor-keymap)
    (add-to-list 'minor-mode-map-alist
		 (cons 'ede-minor-mode
		       ede-minor-keymap))))

(defun ede-minor-mode (&optional arg)
  "Project Automake minor mode.
If this file is contained, or could be contained in an automake
controlled project, then this mode should be active.

Project Automake will manage your automake files, and make it very
easy to edit your automake files.

With argument ARG positive, turn on the mode.  Negative, turn off the
mode.  nil means to toggle the mode."
  (setq ede-minor-mode
	(not (or (and (null arg) ede-minor-mode)
		 (<= (prefix-numeric-value arg) 0))))
  (if (and ede-minor-mode (not ede-constructing))
      (progn
	(ede-load-project-file default-directory)
	(setq ede-object (ede-buffer-object)))))
  
(defun global-ede-mode (arg)
  "Turn on variable `ede-minor-mode' mode when ARG is positive.
If ARG is negative, disable.  Toggle otherwise."
  (interactive "P")
  (if (not arg)
      (if (member 'ede-minor-mode find-file-hooks)
	  (global-ede-mode -1)
	(global-ede-mode 1))
    (if (or (eq arg t) (> arg 0))
	(add-hook 'find-file-hooks (lambda () (ede-minor-mode 1)))
      (remove-hook 'find-file-hooks (lambda () (ede-minor-mode 1))))
    (let ((b (buffer-list)))
      (while b
	(if (buffer-file-name (car b))
	    (save-excursion
	      (set-buffer (car b))
	      (ede-minor-mode arg)))
	(setq b (cdr b))))))

;;; Interactive method invocations
;;
(defun ede (file)
  "Start up EDE on something.
Argument FILE is the file or directory to load a project from."
  (interactive "fProject File: ")
  (if (not (file-exists-p file))
      (ede-new (file))
    (ede-load-project-file (file-name-directory file))))

(defun ede-new (type)
  "Create a new project starting of project type TYPE."
  (interactive
   (list (completing-read "Project Type: "
			  (object-assoc-list :name ede-project-class-files)
			  nil t)))
  (let* ((obj (object-assoc type :name ede-project-class-files))
	 (nobj (make-instance (oref obj :class-sym)
			      :name (read-string "Name: ")
			      :file (oref obj :proj-file))))
    (ede-commit-project nobj))
  (message "Project created and saved.  You may now create targets."))

(defun ede-invoke-method (sym &rest args)
  "Invoke method SYM on the current buffer's project object.
ARGS are additional arguments to pass to method sym."
  (if (not ede-object)
      (error "Cannot invoke %s for %s" (symbol-name sym)
	     (buffer-name)))
  (apply sym ede-object args))

(defun ede-rescan-toplevel ()
  "Rescan all project files."
  (interactive)
  (let ((toppath (ede-toplevel-project default-directory))
	(ede-deep-rescan t))
    (project-rescan (ede-load-project-file toppath))))

(defun ede-customize ()
  "Customize the current project file."
  (interactive)
  (eieio-customize (ede-current-project)))

(defun ede-new-target ()
  "Create a new target specific to this type of project file."
  (interactive)
  (project-new-target (ede-current-project)))

(defun ede-delete-target (target)
  "Delete TARGET from the current project."
  (interactive (list
		(let ((ede-object (ede-current-project)))
		  (ede-invoke-method 'project-interactive-select-target
				     "Target: "))))
  (project-delete-target target))

(defun ede-add-file (target)
  "Add the current buffer to a TARGET in the current project."
  (interactive (list
		(let ((ede-object (ede-current-project)))
		  (ede-invoke-method 'project-interactive-select-target
				     "Target: "))))
  (project-add-file target (buffer-file-name))
  (setq ede-object target))

(defun ede-remove-file ()
  "Remove the current file from targets."
  (interactive)
  (if (not ede-object)
      (error "Cannot invoke remove-file for %s" (buffer-name)))
  (if (y-or-n-p (format "Remove from %s? " (ede-name ede-object)))
      (progn
	(project-remove-file ede-object (ede-convert-path (ede-current-project)
							  (buffer-file-name)))
	(setq ede-object nil))))

(defun ede-edit-file-target ()
  "Enter the project file to hand edit the current buffer's target."
  (interactive)
  (ede-invoke-method 'project-edit-file-target))

(defun ede-compile-project ()
  "Compile the current project."
  (interactive)
  (let ((ede-object (ede-current-project)))
    (ede-invoke-method 'project-compile-project)))

(defun ede-compile-target ()
  "Compile the current buffer's associated target."
  (interactive)
  (ede-invoke-method 'project-compile-target))

(defun ede-debug-target ()
  "Debug the current buffer's assocated target."
  (interactive)
  (ede-invoke-method 'project-debug-target))

(defun ede-make-dist ()
  "Create a distribution from the current project."
  (interactive)
  (let ((ede-object (ede-current-project)))
    (ede-invoke-method 'project-make-dist)))


;;; EDE project target baseline methods.
;;
;;  If you are developing a new project type, you need to implement
;;  all of these methods, unless, of course, they do not make sense
;;  for your particular project.
;;
;;  Your targets should inherit from `ede-target', and your project
;;  files should inherit from `ede-project'.  Create the appropriate
;;  methods based on those below.

(defmethod project-interactive-select-target ((this ede-project) prompt)
  "Interactivly query for a target that exists in project THIS."
  (let ((ob (object-assoc-list :name (oref this :targets))))
    (cdr (assoc (completing-read prompt ob nil t) ob))))

(defmethod project-add-file ((ot ede-target) file)
  "Add the current buffer into a project."
  (error "add-file not supported by %s" (object-name ot)))

(defmethod project-remove-file ((ot ede-target) fnnd)
  "Remove the current buffer from any project targets."
  (error "remove-file not supported by %s" (object-name ot)))

(defmethod project-edit-file-target ((ot ede-target))
  "Edit the target OT associated w/ this file."
  (find-file (oref (ede-current-project) :file)))

(defmethod project-new-target ((proj ede-project))
  "Create a new target.  It is up to the project PROG to get the name."
  (error "new-target not supported by %s" (object-name proj)))

(defmethod project-delete-target ((ot ede-target))
  "Delete the current target from it's parent project."
  (error "add-file not supported by %s" (object-name ot)))

(defmethod project-compile-project ((obj ede-project) &optional command)
  "Compile the entire current project.
Argument COMMAND is the command to use when compiling."
  (error "compile-project not supported by %s" (object-name obj)))

(defmethod project-compile-target ((obj ede-target) &optional command)
  "Compile the current target.
Argument COMMAND is the command to use for compiling the target."
  (error "compile-target not supported by %s" (object-name obj)))

(defmethod project-debug-target ((obj ede-target))
  "Run the current project target in a debugger."
  (error "debug-target not supported by %s" (object-name obj)))

(defmethod project-make-dist ((this ede-project))
  "Build a distribution for the project based on THIS target."
  (error "make-dist not supported by %s" (object-name this)))

;;; Default methods for EDE classes
;;
;; These are methods which you might want to override, but there is
;; no need to in most situations because they are either a) simple, or
;; b) cosmetic.

(defmethod ede-name ((this ede-target))
  "Return the name of this targt."
  (oref this :name))

(defmethod ede-target-name ((this ede-target))
  "Return the name of this target, suitable for make or debug style commands."
  (oref this :name))

(defmethod ede-name ((this ede-project))
  "Return a short-name for this project file.
Do this by extracting the lowest directory name."
  (oref this :name))

(defmethod ede-description ((this ede-project))
  "Return a description suitible for the minibuffer about THIS."
  (format "Project %s: %d subprojects, %d targets."
	  (ede-name this) (length (oref this :subproj)) 
	  (length (oref this :targets))))

(defmethod ede-description ((this ede-target))
  "Return a description suitible for the minibuffer about THIS."
  (format "Target %s: with %d source files."
	  (ede-name this) (length (oref this :source))))

(defmethod ede-convert-path ((this ede-project) path)
  "Convert path in a standard way for a given project.
Default to making it project relative."
  (let ((pp (file-name-directory (expand-file-name (oref this :file))))
	(fp (expand-file-name path)))
    (if (string-match (regexp-quote pp) fp)
	(substring fp (match-end 0))
      (error "Cannot convert relativize path %s." fp))))

;;; EDE project-autoload methods
;;
(defmethod ede-dir-to-projectfile ((this ede-project-autoload) dir)
  "Return a full file name of the project file found in DIR for THIS.
Return nil if the project file does not exist."
  (let ((f (concat dir (oref this :proj-file))))
    (and (file-exists-p f) f)))

;;; EDE basic functions
;;
(defun ede-directory-project-p (dir)
  "Return a project description object if DIR has a project.
This depends on an up to day `ede-project-class-files' variable."
  (let ((types ede-project-class-files)
	(ret nil))
    ;; Loop over all types, loading in the first type that we find.
    (while (and types (not ret))
      (if (ede-dir-to-projectfile (car types) dir)
	  (progn
	    ;; We found one!  Require it now since we will need it.
	    (require (oref (car types) :file))
	    (setq ret (car types))))
      (setq types (cdr types)))
    ret))

(defun ede-toplevel-project (path)
  "Starting with PATH, find the toplevel project directory."
  (let ((toppath nil) (newpath nil))
    ;; Loop up to the topmost project, and then load that single
    ;; project, and it's sub projects.  When we are done, identify the
    ;; sub-project object belonging to file.
    (setq toppath path newpath path)
    (while (ede-directory-project-p newpath)
      (setq toppath newpath newpath
	    (file-name-directory (substring toppath 0 (1- (length toppath))))))
    toppath))

(defun ede-load-project-file (file)
  "Project file independent way to read in FILE."
  (let* ((path (expand-file-name (file-name-directory file)))
	 (pfc (ede-directory-project-p path))
	 (projtoload nil)
	 (toppath nil)
	 (o nil))
    (if (or (not pfc) ede-constructing)
	nil
      (setq toppath (ede-toplevel-project path))
      ;; We found the top-most directory.  Check to see if we already
      ;; have an object defining it's project.
      (setq pfc (ede-directory-project-p toppath))
      ;; See if it's been loaded before
      (setq o (object-assoc (ede-dir-to-projectfile pfc toppath) :file
			    ede-projects))
      (if (not o)
	  ;; If not, get it now.
	  (let ((ede-constructing t) (afo nil))
	    (setq o (funcall (oref pfc :load-type) toppath))
	    (setq ede-projects (cons o ede-projects))))
      (let (tocheck found)
	;; Now find the project file belonging to FILE!
	(setq tocheck (list o))
	(setq file (ede-dir-to-projectfile pfc (expand-file-name path)))
	(while (and tocheck (not found))
	  (if (string= file (oref (car tocheck) :file))
	      (setq found (car tocheck)))
	  (setq tocheck
		(append (cdr tocheck) (oref (car tocheck) :subproj))))
	(if (not found)
	    (error "No project for %s, but passes project-p test" file))
	found))))

(defun ede-current-project ()
  "Return the current project file."
  (ede-load-project-file default-directory))

(defun ede-buffer-object (&optional buffer)
  "Return the target object for BUFFER."
  (if (not buffer) (setq buffer (current-buffer)))
  (let ((po (ede-current-project)))
    (if po (setq ede-object (ede-find-target po buffer)))))

(defun ede-maybe-checkout (&optional buffer)
  "Check BUFFER out of VC if necessary."
  (save-excursion
    (if buffer (set-buffer buffer))
    (if (and buffer-read-only vc-mode
	     (y-or-n-p "Checkout Makefile.am from VC? "))
	(vc-toggle-read-only))))
    

;;; Hooks & Autoloads
;;
;;  These let us watch various activities, and respond apropriatly.

(add-hook 'edebug-setup-hook
	  (lambda ()
	    (def-edebug-spec ede-with-projectfile 
	      (form def-body))))

(autoload 'ede-speedbar "ede-speedbar" "Run speedbar in EDE project mode." t)

(provide 'ede)

;;; ede.el ends here
