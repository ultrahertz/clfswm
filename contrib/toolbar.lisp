;;; --------------------------------------------------------------------------
;;; CLFSWM - FullScreen Window Manager
;;;
;;; --------------------------------------------------------------------------
;;; Documentation: Toolbar
;;; --------------------------------------------------------------------------
;;;
;;; (C) 2011 Philippe Brochard <hocwp@free.fr>
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
;;; Documentation: If you want to use this file, just add this line in
;;; your configuration file:
;;;
;;;   (load-contrib "toolbar.lisp")
;;;
;;; --------------------------------------------------------------------------

(in-package :clfswm)

(format t "Loading Toolbar code... ")

(defstruct toolbar root-x root-y root direction size thickness placement refresh-delay
           autohide modules clickable font window gc border-size)

(defparameter *toolbar-list* nil)
(defparameter *toolbar-module-list* nil)

;;; CONFIG - Toolbar window string colors
(defconfig *toolbar-window-font-string* *default-font-string*
  'Toolbar "Toolbar window font string")
(defconfig *toolbar-window-background* "black"
  'Toolbar "Toolbar Window background color")
(defconfig *toolbar-window-foreground* "green"
  'Toolbar "Toolbar Window foreground color")
(defconfig *toolbar-window-border* "red"
  'Toolbar "Toolbar Window border color")
(defconfig *toolbar-default-border-size* 0
  'Toolbar "Toolbar Window border size")
(defconfig *toolbar-window-transparency* *default-transparency*
  'Toolbar "Toolbar window background transparency")
(defconfig *toolbar-default-thickness* 20
  'Toolbar "Toolbar default thickness")
(defconfig *toolbar-default-refresh-delay* 30
  'Toolbar "Toolbar default refresh delay")
(defconfig *toolbar-default-autohide* nil
  'Toolbar "Toolbar default autohide value")
(defconfig *toolbar-sensibility* 10
  'Toolbar "Toolbar sensibility in pixels")

(defconfig *toolbar-window-placement* 'top-left-placement
  'Placement "Toolbar window placement")

(defun toolbar-symbol-fun (name)
  (create-symbol 'toolbar- name '-module))

(defun toolbar-adjust-root-size (toolbar)
  (unless (toolbar-autohide toolbar)
    (let ((root (toolbar-root toolbar))
          (placement-name (symbol-name (toolbar-placement toolbar)))
          (thickness (+ (toolbar-thickness toolbar) (* 2 (toolbar-border-size toolbar)))))
      (when (root-p root)
        (case (toolbar-direction toolbar)
          (:horiz (cond ((search "TOP" placement-name)
                         (incf (root-y root) thickness)
                         (decf (root-h root) thickness))
                        ((search "BOTTOM" placement-name)
                         (decf (root-h root) thickness))))
          (t (cond ((search "LEFT" placement-name)
                    (incf (root-x root) thickness)
                    (decf (root-w root) thickness))
                   ((search "RIGHT" placement-name)
                    (decf (root-w root) thickness)))))))))


(defun toolbar-draw-text (toolbar pos1 pos2 text)
  "pos1: percent, pos2: pixels"
  (labels ((horiz-text ()
             (let* ((height (- (xlib:font-ascent (toolbar-font toolbar)) (xlib:font-descent (toolbar-font toolbar))))
                    (dy (truncate (+ pos2 (/ height 2))))
                    (width (xlib:text-width (toolbar-font toolbar) text))
                    (pos (truncate (/ (* (- (xlib:drawable-width (toolbar-window toolbar)) width) pos1) 100))))
               (xlib:draw-glyphs *pixmap-buffer* (toolbar-gc toolbar) pos dy text)))
           (vert-text ()
             (let* ((width (xlib:max-char-width (toolbar-font toolbar)))
                    (dx (truncate (- pos2 (/ width 2))))
                    (dpos (xlib:max-char-ascent (toolbar-font toolbar)))
                    (height (* dpos (length text)))
                    (pos (+ (truncate (/ (* (- (xlib:drawable-height (toolbar-window toolbar)) height
                                               (xlib:max-char-descent (toolbar-font toolbar)))
                                            pos1) 100))
                            (xlib:font-ascent (toolbar-font toolbar)))))
               (loop for c across text
                  do (xlib:draw-glyphs *pixmap-buffer* (toolbar-gc toolbar) dx pos (string c))
                    (incf pos dpos)))))
    (case (toolbar-direction toolbar)
      (:horiz (horiz-text))
      (:vert (vert-text)))))



(defun refresh-toolbar (toolbar)
  (add-timer (toolbar-refresh-delay toolbar)
             (lambda ()
               (refresh-toolbar toolbar))
             :refresh-toolbar)
  (clear-pixmap-buffer (toolbar-window toolbar) (toolbar-gc toolbar))
  (dolist (module (toolbar-modules toolbar))
    (let ((fun (toolbar-symbol-fun (first module))))
      (when (fboundp fun)
        (funcall fun toolbar module))))
  (copy-pixmap-buffer (toolbar-window toolbar) (toolbar-gc toolbar)))

(defun toolbar-in-sensibility-zone-p (toolbar root-x root-y)
  (let* ((tb-win (toolbar-window toolbar))
         (win-x (xlib:drawable-x tb-win))
         (win-y (xlib:drawable-y tb-win))
         (width (xlib:drawable-width tb-win))
         (height (xlib:drawable-height tb-win))
         (tb-dir (toolbar-direction toolbar) )
         (placement-name (symbol-name (toolbar-placement toolbar))))
    (or (and (equal tb-dir :horiz) (search "TOP" placement-name)
             (<= root-y win-y (+ root-y *toolbar-sensibility*))
             (<= win-x root-x (+ win-x width)) (toolbar-autohide toolbar))
        (and (equal tb-dir :horiz) (search "BOTTOM" placement-name)
             (<= (+ win-y height (- *toolbar-sensibility*)) root-y (+ win-y height))
             (<= win-x root-x (+ win-x width)) (toolbar-autohide toolbar))
        (and (equal tb-dir :vert) (search "LEFT" placement-name)
             (<= root-x win-x (+ root-x *toolbar-sensibility*))
             (<= win-y root-y (+ win-y height)) (toolbar-autohide toolbar))
        (and (equal tb-dir :vert) (search "RIGHT" placement-name)
             (<= (+ win-x width (- *toolbar-sensibility*)) root-x (+ win-x width))
             (<= win-y root-y (+ win-y height)) (toolbar-autohide toolbar)))))

(use-event-hook :exposure)
(use-event-hook :button-press)
(use-event-hook :motion-notify)
(use-event-hook :leave-notify)


(defun toolbar-add-exposure-hook (toolbar)
  (define-event-hook :exposure (window)
    (when (and (xlib:window-p window) (xlib:window-equal (toolbar-window toolbar) window))
      (refresh-toolbar toolbar))))

(defun toolbar-add-hide-button-press-hook (toolbar)
  (let ((hide t))
    (define-event-hook :button-press (code root-x root-y)
      (when (= code 1)
        (let* ((tb-win (toolbar-window toolbar)))
          (when (toolbar-in-sensibility-zone-p toolbar root-x root-y)
            (if hide
                (progn
                  (map-window tb-win)
                  (raise-window tb-win)
                  (refresh-toolbar toolbar))
                (hide-window tb-win))
            (setf hide (not hide))
            (wait-mouse-button-release)
            (stop-button-event)
            (throw 'exit-handle-event nil)))))))

(defun toolbar-add-hide-motion-hook (toolbar)
  (define-event-hook :motion-notify (root-x root-y)
    (unless (compress-motion-notify)
      (when (toolbar-in-sensibility-zone-p toolbar root-x root-y)
        (map-window (toolbar-window toolbar))
        (raise-window (toolbar-window toolbar))
        (refresh-toolbar toolbar)
        (throw 'exit-handle-event nil)))))

(defun toolbar-add-hide-leave-hook (toolbar)
  (define-event-hook :leave-notify (window root-x root-y)
    (when (and (xlib:window-equal (toolbar-window toolbar) window)
               (not (in-window (toolbar-window toolbar) root-x root-y)))
      (hide-window window)
      (throw 'exit-handle-event nil))))

(defun define-toolbar-hooks (toolbar)
  (toolbar-add-exposure-hook toolbar)
  (when (toolbar-clickable toolbar)
    (define-event-hook :button-press (code root-x root-y)
      (dbg code root-x root-y)))
  (case (toolbar-autohide toolbar)
    (:click (toolbar-add-hide-button-press-hook toolbar))
    (:motion (toolbar-add-hide-motion-hook toolbar)
             (toolbar-add-hide-leave-hook toolbar))))

(defun set-clickable-toolbar (toolbar)
  (dolist (module *toolbar-module-list*)
    (when (and (member (first module) (toolbar-modules toolbar)
                       :test (lambda (x y) (equal x (first y))))
               (second module))
      (setf (toolbar-clickable toolbar) t))))




(let ((windows-list nil))
  (defun is-toolbar-window-p (win)
    (and (xlib:window-p win) (member win windows-list :test 'xlib:window-equal)))

  (defun close-toolbar (toolbar)
    (erase-timer :refresh-toolbar-window)
    (setf *never-managed-window-list*
          (remove (list #'is-toolbar-window-p nil)
                  *never-managed-window-list* :test #'equal))
    (awhen (toolbar-gc toolbar)
      (xlib:free-gcontext it))
    (awhen (toolbar-window toolbar)
      (xlib:destroy-window it))
    (awhen (toolbar-font toolbar)
      (xlib:close-font it))
    (xlib:display-finish-output *display*)
    (setf (toolbar-window toolbar) nil
          (toolbar-gc toolbar) nil
          (toolbar-font toolbar) nil))

  (defun open-toolbar (toolbar)
    (let ((root (find-root-by-coordinates (toolbar-root-x toolbar) (toolbar-root-y toolbar))))
      (when (root-p root)
        (setf (toolbar-root toolbar) root)
        (let ((*get-current-root-fun* (lambda () root)))
          (setf (toolbar-font toolbar) (xlib:open-font *display* *toolbar-window-font-string*))
          (let* ((width (if (equal (toolbar-direction toolbar) :horiz)
                            (round (/ (* (root-w root) (toolbar-size toolbar)) 100))
                            (toolbar-thickness toolbar)))
                 (height (if (equal (toolbar-direction toolbar) :horiz)
                             (toolbar-thickness toolbar)
                             (round (/ (* (root-h root) (toolbar-size toolbar)) 100)))))
            (with-placement ((toolbar-placement toolbar) x y width height (toolbar-border-size toolbar))
              (setf (toolbar-window toolbar) (xlib:create-window :parent *root*
                                                                 :x x
                                                                 :y y
                                                                 :width width
                                                                 :height height
                                                                 :background (get-color *toolbar-window-background*)
                                                                 :border-width (toolbar-border-size toolbar)
                                                                 :border (when (plusp (toolbar-border-size toolbar))
                                                                           (get-color *toolbar-window-border*))
                                                                 :colormap (xlib:screen-default-colormap *screen*)
                                                                 :event-mask '(:exposure :key-press :leave-window))
                    (toolbar-gc toolbar) (xlib:create-gcontext :drawable (toolbar-window toolbar)
                                                               :foreground (get-color *toolbar-window-foreground*)
                                                               :background (get-color *toolbar-window-background*)
                                                               :font (toolbar-font toolbar)
                                                               :line-style :solid))
              (push (toolbar-window toolbar) windows-list)
              (setf (window-transparency (toolbar-window toolbar)) *toolbar-window-transparency*)
              (push (list #'is-toolbar-window-p nil) *never-managed-window-list*)
              (map-window (toolbar-window toolbar))
              (raise-window (toolbar-window toolbar))
              (refresh-toolbar toolbar)
              (when (toolbar-autohide toolbar)
                (hide-window (toolbar-window toolbar)))
              (xlib:display-finish-output *display*)
              (set-clickable-toolbar toolbar)
              (define-toolbar-hooks toolbar))))))))

(defun open-all-toolbars ()
  "Open all toolbars"
  (dolist (toolbar *toolbar-list*)
    (open-toolbar toolbar))
  (dolist (toolbar *toolbar-list*)
    (toolbar-adjust-root-size toolbar)))

(defun close-all-toolbars ()
  (dolist (toolbar *toolbar-list*)
    (close-toolbar toolbar)))


(defun add-toolbar (root-x root-y direction size placement modules
                    &key (autohide *toolbar-default-autohide*))
  "Add a new toolbar.
     root-x, root-y: root coordinates
     direction: one of :horiz or :vert
     size: toolbar size in percent of root size"
  (let ((toolbar (make-toolbar :root-x root-x :root-y root-y
                      :direction direction :size size
                      :thickness *toolbar-default-thickness*
                      :placement placement
                      :autohide autohide
                      :refresh-delay *toolbar-default-refresh-delay*
                      :border-size *toolbar-default-border-size*
                      :modules modules)))
    (push toolbar *toolbar-list*)
    toolbar))


(add-hook *init-hook* 'open-all-toolbars)
(add-hook *close-hook* 'close-all-toolbars)


(defmacro define-toolbar-module ((name &optional clickable) &body body)
  (let ((symbol-fun (toolbar-symbol-fun name)))
    `(progn
       (pushnew (list ',name ,clickable) *toolbar-module-list*)
       (defun ,symbol-fun (toolbar module)
         ,@body))))




;;;
;;; Modules definitions
;;;
(define-toolbar-module (clock)
  "The clock module"
  (multiple-value-bind (s m h)
      (get-decoded-time)
    (declare (ignore s))
    (toolbar-draw-text toolbar (second module) (/ *toolbar-default-thickness* 2)
                       (format nil "~2,'0D:~2,'0D" h m))))


(define-toolbar-module (label)
  "The label module"
  (toolbar-draw-text toolbar (second module) (/ *toolbar-default-thickness* 2)
                     "Label"))


(define-toolbar-module (clickable-clock t)
  "The clock module (clickable)"
  (multiple-value-bind (s m h)
      (get-decoded-time)
    (declare (ignore s))
    (toolbar-draw-text toolbar (second module) (/ *toolbar-default-thickness* 2)
                       (format nil "Click:~2,'0D:~2,'0D" h m))))


(format t "done~%")