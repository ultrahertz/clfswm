;;; --------------------------------------------------------------------------
;;; CLFSWM - FullScreen Window Manager
;;;
;;; --------------------------------------------------------------------------
;;; Documentation: Expose functions - An expose like.
;;; --------------------------------------------------------------------------
;;;
;;; (C) 2010 Philippe Brochard <hocwp@free.fr>
;;;
;;; This program is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program; if not, write to the Free Software
;;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
;;;
;;; --------------------------------------------------------------------------

(in-package :clfswm)

(defparameter *expose-font* nil)
(defparameter *expose-windows-list* nil)

(defun leave-expose-mode ()
  "Leave the expose mode"
  (throw 'exit-expose-loop nil))

(defun valid-expose-mode ()
  "Valid the expose mode"
  (throw 'exit-expose-loop t))

(defun mouse-leave-expose-mode (window root-x root-y)
  "Leave the expose mode"
  (declare (ignore window root-x root-y))
  (throw 'exit-expose-loop nil))

(defun mouse-valid-expose-mode (window root-x root-y)
  "Valid the expose mode"
  (declare (ignore window root-x root-y))
  (throw 'exit-expose-loop t))


(define-handler expose-mode :key-press (code state)
  (funcall-key-from-code *expose-keys* code state))

(define-handler expose-mode :button-press (code state window root-x root-y)
  (funcall-button-from-code *expose-mouse* code state window root-x root-y *fun-press*))

(define-handler expose-mode :exposure ()
  (expose-draw-letter))


(add-hook *binding-hook* 'set-default-expose-keys)

(defun set-default-expose-keys ()
  (define-expose-key ("Escape") 'leave-expose-mode)
  (define-expose-key ("g" :control) 'leave-expose-mode)
  (define-expose-key ("Escape" :alt) 'leave-expose-mode)
  (define-expose-key ("g" :control :alt) 'leave-expose-mode)
  (define-expose-key ("Return") 'valid-expose-mode)
  (define-expose-key ("space") 'valid-expose-mode)
  (define-expose-key ("Tab") 'valid-expose-mode)
  (define-expose-key ("Right") 'speed-mouse-right)
  (define-expose-key ("Left") 'speed-mouse-left)
  (define-expose-key ("Down") 'speed-mouse-down)
  (define-expose-key ("Up") 'speed-mouse-up)
  (define-expose-key ("Left" :control) 'speed-mouse-undo)
  (define-expose-key ("Up" :control) 'speed-mouse-first-history)
  (define-expose-key ("Down" :control) 'speed-mouse-reset)
  (define-expose-mouse (1) 'mouse-valid-expose-mode)
  (define-expose-mouse (2) 'mouse-leave-expose-mode)
  (define-expose-mouse (3) 'mouse-leave-expose-mode))

(defmacro define-expose-letter-keys ()
  (labels ((produce-name (n)
	     (symb "%" "expose-fun-key-" n "%")))
    `(progn
       ,@(loop for n from 0 to 25
	    collect `(progn
		       (defun ,(produce-name n) ()
			 ,(format nil "Select child '~A' (~A)" (number->char n) n)
			 (let ((child (nth ,n *expose-windows-list*)))
			   (when child
			     (xlib:warp-pointer *root* (xlib:drawable-x (first child)) (xlib:drawable-y (first child)))
			     (when *expose-valid-on-key*
			       (valid-expose-mode)))))
		       (define-expose-key (,(number->char n)) ',(produce-name n)))))))

(define-expose-letter-keys)


(defun expose-draw-letter ()
  (loop for lwin in *expose-windows-list*
       for n from 0 do
       (xlib:draw-glyphs (first lwin) (second lwin)
			 (xlib:max-char-width *expose-font*)
			 (+ (xlib:font-ascent *expose-font*) (xlib:font-descent *expose-font*))
			 (format nil "~A" (number->char n)))))

(defun expose-create-window (child n)
  (declare (ignore n))
  (with-placement (*expose-mode-placement* x y (child-width child) (child-height child))
    (let* ((window (xlib:create-window :parent *root*
				       :x (+ (child-x child) x)
				       :y (+ (child-y child) y)
				       :width (* (xlib:max-char-width *expose-font*) 3)
				       :height (* (xlib:font-ascent *expose-font*) 2)
				       :background (get-color *expose-background*)
				       :border-width 1
				       :border (get-color *expose-border*)
				       :colormap (xlib:screen-default-colormap *screen*)
				       :event-mask '(:exposure :key-press)))
	   (gc (xlib:create-gcontext :drawable window
				     :foreground (get-color *expose-foreground*)
				     :background (get-color *expose-background*)
				     :font *expose-font*
				     :line-style :solid)))
      (map-window window)
      (push (list window gc) *expose-windows-list*))))



(defun expose-mode-display-accel-windows ()
  (let ((n -1))
    (with-all-children-reversed (*current-root* child)
      (when (< n 25)
	(expose-create-window child (incf n)))))
  (setf *expose-windows-list* (nreverse *expose-windows-list*))
  (expose-draw-letter))


(defun expose-windows-generic (first-restore-frame body)
  (setf *expose-font* (xlib:open-font *display* *expose-font-string*)
	*expose-windows-list* nil)
  (xlib:warp-pointer *root* (truncate (/ (xlib:screen-width *screen*) 2))
		     (truncate (/ (xlib:screen-height *screen*) 2)))
  (with-all-frames (first-restore-frame frame)
    (setf (frame-data-slot frame :old-layout) (frame-layout frame)
	  (frame-layout frame) #'tile-space-layout))
  (show-all-children *current-root*)
  (expose-mode-display-accel-windows)
  (let ((grab-keyboard-p (xgrab-keyboard-p))
	(grab-pointer-p (xgrab-pointer-p)))
    (xgrab-pointer *root* 92 93)
    (unless grab-keyboard-p
      (ungrab-main-keys)
      (xgrab-keyboard *root*))
    (when (generic-mode 'expose-mode 'exit-expose-loop
			:original-mode '(main-mode))
      (multiple-value-bind (x y) (xlib:query-pointer *root*)
	(let* ((child (find-child-under-mouse x y))
	       (parent (find-parent-frame child *root-frame*)))
	  (when (and child parent)
	    (pfuncall body parent)
	    (focus-all-children child parent)))))
    (dolist (lwin *expose-windows-list*)
      (awhen (first lwin)
	(xlib:destroy-window it))
      (awhen (second lwin)
	     (xlib:free-gcontext it)))
    (when *expose-font*
      (xlib:close-font *expose-font*))
    (setf *expose-windows-list* nil)
    (with-all-frames (first-restore-frame frame)
      (setf (frame-layout frame) (frame-data-slot frame :old-layout)
	    (frame-data-slot frame :old-layout) nil))
    (show-all-children *current-root*)
    (unless grab-keyboard-p
      (xungrab-keyboard)
      (grab-main-keys))
    (if grab-pointer-p
	(xgrab-pointer *root* 66 67)
	(xungrab-pointer)))
  t)


(defun expose-windows-mode ()
  "Present all windows in the current frame (An expose like)"
  (stop-button-event)
  (expose-windows-generic *current-root* nil))

(defun expose-all-windows-mode ()
  "Present all windows in all frames (An expose like)"
  (stop-button-event)
  (switch-to-root-frame :show-later t)
  (expose-windows-generic *root-frame*
			  (lambda (parent)
			    (hide-all-children *root-frame*)
			    (setf *current-root* parent))))