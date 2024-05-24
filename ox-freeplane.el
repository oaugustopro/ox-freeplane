;;; ox-freeplane.el --- Freeplane Mindmap Back-End for Org Export Engine

;; Copyright (C) 2013, 2014  Free Software Foundation, Inc.

;; Author: Jambunathan K <kjambunathan at gmail dot com>
;; Keywords: outlines, hypermedia, calendar, wp

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
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This library implements a Freeplane Mindmap back-end for Org generic
;; exporter.

;; To test it, run:
;;
;;   M-x org-freeplane-export-to-freeplane
;;
;; in an Org mode buffer.  See ox.el for more details on how this
;; exporter works.

;;; Code:

;;; Dependencies

(require 'ox-html)
(require 'cl-lib)


;;; Define Back-End

(org-export-define-derived-backend 'freeplane 'html
  ;;  :export-block "FREEPLANE"
  :menu-entry
  '(?f "Export to Freeplane Mindmap"
       ((?f "As Freeplane Mindmap file" org-freeplane-export-to-freeplane)
        (?o "As Freeplane Mindmap file and open"
            (lambda (a s v b)
              (if a (org-freeplane-export-to-freeplane t s v b)
                (org-open-file (org-freeplane-export-to-freeplane nil s v b)))))))
  :translate-alist '((headline . org-freeplane-headline)
                     (template . org-freeplane-template)
                     (inner-template . org-freeplane-inner-template)
                     (section . org-freeplane-section)
                     (entity . org-freeplane-entity))
  :filters-alist '((:filter-options . org-freeplane-options-function)
                   (:filter-final-output . org-freeplane-final-function)))



;;; User Configuration Variables

(defgroup org-export-freeplane nil
  "Options for exporting Org mode files to Freeplane Mindmap."
  :tag "Org Export Freeplane Mindmap"
  :group 'org-export)

(defcustom org-freeplane-styles
  '((default . "<node>\n</node>")
    (0 . "<node COLOR=\"#000000\">\n<font NAME=\"SansSerif\" SIZE=\"20\"/>\n</node>")
    (1 . "<node COLOR=\"#0033ff\">\n<edge STYLE=\"sharp_bezier\" WIDTH=\"8\"/>\n<font NAME=\"SansSerif\" SIZE=\"18\"/>\n</node>")
    (2 . "<node COLOR=\"#00b439\">\n<edge STYLE=\"bezier\" WIDTH=\"thin\"/>\n<font NAME=\"SansSerif\" SIZE=\"16\"/>\n</node>")
    (3 . "<node COLOR=\"#990000\" FOLDED=\"true\">\n<font NAME=\"SansSerif\" SIZE=\"14\"/>\n</node>")
    (4 . "<node COLOR=\"#111111\">\n</node>"))
  "List of Freeplane node styles.
Each entry is of the form (STYLE-NAME . STYLE-SPEC).  STYLE-NAME
can be one of an integer (signifying an outline level), a string
or the symbol `default'.  STYLE-SPEC, a string, is a Freeplane
node style."
  :type '(alist :options (default 0 1 2 3)
                :key-type (choice :tag "Style tag"
                                  (integer :tag "Outline level")
                                  (const :tag "Default value" default)
                                  (string :tag "Node style"))
                :value-type (string :tag "Style spec"))
  :group 'org-export-freeplane)

(defcustom org-freeplane-style-map-function 'org-freeplane-style-map--automatic
  "Function to map an Org element to its node style.
The mapping function takes two arguments: an Org ELEMENT and INFO.
ELEMENT can be one of the following types - `org-data',
`headline' or `section'.  INFO is a plist holding contextual
information during export.  The function must return a STYLE-SPEC
to be applied to ELEMENT.

See `org-freeplane-style-map--automatic' for a sample style
function.  See `org-freeplane-styles' for a list of named styles."
  :type '(radio
          (function-item org-freeplane-style-map--automatic)
          (function-item org-freeplane-style-map--default)
          function)
  :group 'org-export-freeplane)

(defcustom org-freeplane-section-format 'note
  "Specify how outline sections are to be formatted.
If `inline', append it to the contents of its heading node.  If
`note', attach it as a note to its heading node.  If `node',
attach it as a separate node to its heading node.

Use `note', if the input Org file contains large sections.  Use
`node', if the Org file contains mid-sized sections that need to
stand apart.  Otherwise, use `inline'."
  :type '(choice
          (const :tag "Append to outline title" inline)
          (const :tag "Attach as a note" note)
          (const :tag "Create a separate node" node))
  :group 'org-export-freeplane)

;;;; Debugging

(defcustom org-freeplane-pretty-output nil
  "Enable this to generate pretty Freeplane Mindmap."
  :type 'boolean
  :group 'org-export-freeplane)


;;; Internal Functions

;;;; XML Manipulation

(defun org-freeplane--serialize (parsed-xml &optional contents)
  "Convert PARSED-XML into an XML string.
PARSED-XML is a parse tree as returned by
`libxml-parse-xml-region'.  CONTENTS is an optional string.

Ignore CONTENTS, if PARSED-XML is not a sole XML element.
Otherwise, append CONTENTS to the contents of the top-level element
in PARSED-XML.

This is an inverse function of `libxml-parse-xml-region'.

For purposes of Freeplane export, PARSED-XML is a node style
specification - \"<node ...>...</node>\" - as a parse tree."
  (when contents
    (cl-assert (symbolp (car parsed-xml))))
  (cond
   ((null parsed-xml) "")
   ((stringp parsed-xml) parsed-xml)
   ((symbolp (car parsed-xml))
    (let ((attributes (mapconcat
                       (lambda (av)
                         (format "%s=\"%s\"" (car av) (cdr av)))
                       (cadr parsed-xml) " ")))
      (if (or (cddr parsed-xml) contents)
          (format "\n<%s%s>%s\n</%s>"
                  (car parsed-xml)
                  (if (string= attributes "") "" (concat " " attributes))
                  (concat (org-freeplane--serialize (cddr parsed-xml))
                          contents)
                  (car parsed-xml))
        (format "\n<%s%s/>"
                (car parsed-xml)
                (if (string= attributes "") "" (concat " " attributes))))))
   (t (mapconcat #'org-freeplane--serialize parsed-xml ""))))

(defun org-freeplane--parse-xml (xml-string)
  "Return parse tree for XML-STRING using `libxml-parse-xml-region'.
For purposes of Freeplane export, XML-STRING is a node style
specification - \"<node ...>...</node>\" - as a string."
  (with-temp-buffer
    (insert (or xml-string ""))
    (libxml-parse-xml-region (point-min) (point-max))))

;;;; Style mappers :: Default and Automatic layout

(defun org-freeplane-style-map--automatic (element info)
  "Return a node style corresponding to relative outline level of ELEMENT.
ELEMENT can be any of the following types - `org-data',
`headline' or `section'.  See `org-freeplane-styles' for style
mappings of different outline levels."
  (let ((style-name
         (cl-case (org-element-type element)
           (headline
            (org-export-get-relative-level element info))
           (section
            (let ((parent (org-export-get-parent-headline element)))
              (if (not parent) 1
                (1+ (org-export-get-relative-level parent info)))))
           (t 0))))
    (or (assoc-default style-name org-freeplane-styles)
        (assoc-default 'default org-freeplane-styles)
        "<node></node>")))

(defun org-freeplane-style-map--default (element info)
  "Return the default style for all ELEMENTs.
ELEMENT can be any of the following types - `org-data',
`headline' or `section'.  See `org-freeplane-styles' for current
value of default style."
  (or (assoc-default 'default org-freeplane-styles)
      "<node></node>"))

;;;; Helpers :: Retrieve, apply Freeplane styles

(defun org-freeplane--get-node-style (element info)
  "Return Freeplane node style applicable for HEADLINE.
ELEMENT is an Org element of type `org-data', `headline' or
`section'.  INFO is a plist holding contextual information."
  (unless (fboundp org-freeplane-style-map-function)
    (setq org-freeplane-style-map-function 'org-freeplane-style-map--default))
  (let ((style (funcall org-freeplane-style-map-function element info)))
    ;; Sanitize node style.

    ;; Loop through the attributes of node element and purge those
    ;; attributes that look suspicious.  This is an extra bit of work
    ;; that allows one to copy verbatim node styles from an existing
    ;; Freeplane Mindmap file without messing with the exported data.
    (let* ((data (org-freeplane--parse-xml style))
           (attributes (cadr data))
           (ignored-attrs '(POSITION FOLDED TEXT CREATED ID
                                     MODIFIED)))
      (let (attr)
        (while (setq attr (pop ignored-attrs))
          (setq attributes (assq-delete-all attr attributes))))
      (when data (setcar (cdr data) attributes))
      (org-freeplane--serialize data))))

(defun org-freeplane--build-stylized-node (style-1 style-2 &optional contents)
  "Build a Freeplane node with style STYLE-1 + STYLE-2 and add CONTENTS to it.
STYLE-1 and STYLE-2 are Freeplane node styles as a string.
STYLE-1 is the base node style and STYLE-2 is the overriding
style that takes precedence over STYLE-1.  CONTENTS is a string.

Return value is a Freeplane node with the following properties:

  1. The attributes of \"<node ...> </node>\" element is the union
     of corresponding attributes of STYLE-1 and STYLE-2.  When
     STYLE-1 and STYLE-2 specify values for the same attribute
     name, choose the attribute value from STYLE-2.

  2. The children of \"<node ...> </node>\" element is the union of
     top-level children of STYLE-1 and STYLE-2 with CONTENTS
     appended to it.  When STYLE-1 and STYLE-2 share a child
     element of the same type, the value chosen is that from STYLE-2.

For example, merging with the following parameters

  STYLE-1  =>
              <node COLOR=\"#00b439\" STYLE=\"Bubble\">
                <edge STYLE=\"bezier\" WIDTH=\"thin\"/>
                <font NAME=\"SansSerif\" SIZE=\"16\"/>
              </node>

  STYLE-2  =>
              <node COLOR=\"#990000\" FOLDED=\"true\">
                <font NAME=\"SansSerif\" SIZE=\"14\"/>
              </node>

  CONTENTS =>
               <attribute NAME=\"ORGTAG\" VALUE=\"@home\"/>

will result in the following node:

  RETURN   =>
               <node STYLE=\"Bubble\" COLOR=\"#990000\" FOLDED=\"true\">
                 <edge STYLE=\"bezier\" WIDTH=\"thin\"/>
                 <font NAME=\"SansSerif\" SIZE=\"14\"/>
                 <attribute NAME=\"ORGTAG\" VALUE=\"@home\"/>
               </node>."
  (let* ((data1 (org-freeplane--parse-xml (or style-1 "")))
         (data2 (org-freeplane--parse-xml (or style-2 "")))
         (attr1 (cadr data1))
         (attr2 (cadr data2))
         (merged-attr attr2)
         (children1 (cddr data1))
         (children2 (cddr data2))
         (merged-children children2))
    (let (attr)
      (while (setq attr (pop attr1))
        (unless (assq (car attr) merged-attr)
          (push attr merged-attr))))
    (let (child)
      (while (setq child (pop children1))
        (when (or (stringp child) (not (assq (car child) merged-children)))
          (push child merged-children))))
    (let ((merged-data (nconc (list 'node merged-attr) merged-children)))
      (org-freeplane--serialize merged-data contents))))

;;;; Helpers :: Node contents

(defun org-freeplane--richcontent (type contents &optional css-style)
  (let* ((type (cl-case type
                 (note "NOTE")
                 (node "NODE")
                 (t "NODE")))
         (contents (org-trim contents)))
    (if (string= (org-trim contents) "") ""
      (format "\n<richcontent TYPE=\"%s\">%s\n</richcontent>"
              type
              (format "\n<html>\n<head>%s\n</head>\n%s\n</html>"
                      (or css-style "")
                      (format "<body>\n%s\n</body>" contents))))))

(defun org-freeplane--build-node-contents (element contents info)
  (let* ((title (cl-case (org-element-type element)
                  (headline
                   (org-element-property :title element))
                  (org-data
                   (plist-get info :title))
                  (t (error "Shouldn't come here."))))
         (element-contents (org-element-contents element))
         (section (assq 'section element-contents))
         (section-contents
          (let ((backend (org-export-create-backend
                          :parent (org-export-backend-name
                                   (plist-get info :back-end))
                          :transcoders '((section . (lambda (e c i) c))))))
            (org-export-data-with-backend section backend info)))
         (itemized-contents-p (let ((first-child-headline
                                     (org-element-map element-contents
                                         'headline 'identity info t)))
                                (when first-child-headline
                                  (org-export-low-level-p first-child-headline
                                                          info))))
         (node-contents (concat section-contents
                                (when itemized-contents-p
                                  contents))))
    (concat (let ((title (org-export-data title info)))
              (cl-case org-freeplane-section-format
                (inline
                 (org-freeplane--richcontent
                  'node (concat (format "\n<h2>%s</h2>" title)
                                node-contents)))
                (note
                 (concat (org-freeplane--richcontent
                          'node (format "\n<p>%s\n</p>" title))
                         (org-freeplane--richcontent
                          'note node-contents)))
                (node
                 (concat
                  (org-freeplane--richcontent
                   'node (format "\n<p>%s\n</p>" title))
                  (when section
                    (org-freeplane--build-stylized-node
                     (org-freeplane--get-node-style section info) nil
                     (org-freeplane--richcontent 'node node-contents)))))))
            (unless itemized-contents-p
              contents))))


;;; Template

(defun org-freeplane-template (contents info)
  "Return complete document string after Freeplane Mindmap conversion.
CONTENTS is the transcoded contents string.  RAW-DATA is the
original parsed data.  INFO is a plist holding export options."
  (format
   "<map version=\"0.9.0\">\n%s\n</map>"
   (org-freeplane--build-stylized-node
    (org-freeplane--get-node-style nil info) nil
    (let ((org-data (plist-get info :parse-tree)))
      (org-freeplane--build-node-contents org-data contents info)))))

(defun org-freeplane-inner-template (contents info)
  "Return body of document string after Freeplane Mindmap conversion.
CONTENTS is the transcoded contents string.  INFO is a plist
holding export options."
  contents)

;;;; Tags

(defun org-freeplane--tags (tags)
  (mapconcat (lambda (tag)
               (format "\n<attribute NAME=\"%s\" VALUE=\"%s\"/>" tag ""))
             tags "\n"))


;;; Transcode Functions

;;;; Entity

(defun org-freeplane-entity (entity contents info)
  "Transcode an ENTITY object from Org to Freeplane Mindmap.
CONTENTS are the definition itself.  INFO is a plist holding
contextual information."
  (org-element-property :utf-8 entity))

;;;; Headline

(defun org-freeplane-headline (headline contents info)
  "Transcode a HEADLINE element from Org to Freeplane Mindmap.
CONTENTS holds the contents of the headline.  INFO is a plist
holding contextual information."
  ;; Empty contents?
  (setq contents (or contents ""))
  (let* ((numberedp (org-export-numbered-headline-p headline info))
         (level (org-export-get-relative-level headline info))
         (text (org-export-data (org-element-property :title headline) info))
         (todo (and (plist-get info :with-todo-keywords)
                    (let ((todo (org-element-property :todo-keyword headline)))
                      (and todo (org-export-data todo info)))))
         (todo-type (and todo (org-element-property :todo-type headline)))
         (tags (and (plist-get info :with-tags)
                    (org-export-get-tags headline info)))
         (priority (and (plist-get info :with-priority)
                        (org-element-property :priority headline)))
         (section-number (and (not (org-export-low-level-p headline info))
                              (org-export-numbered-headline-p headline info)
                              (mapconcat 'number-to-string
                                         (org-export-get-headline-number
                                          headline info) ".")))
         ;; Create the headline text.
         (full-text (org-export-data (org-element-property :title headline)
                                     info))
         ;; Headline order (i.e, first digit of the section number)
         (headline-order (car (org-export-get-headline-number headline info))))
    (cond
     ;;  1: This is a footnote section: ignore it.
     ((org-element-property :footnote-section-p headline) nil)
     ;;  2. This is a deep sub-tree, export it as a list item.
     ;;         Delegate the actual export to `html' backend.
     ((org-export-low-level-p headline info)
      (org-html-headline headline contents info))
     ;;  3. Standard headline.  Export it as a section.
     (t
      (let* ((section-number (mapconcat 'number-to-string
                                        (org-export-get-headline-number
                                         headline info) "-"))
             (ids (remove 'nil
                          (list (org-element-property :CUSTOM_ID headline)
                                (concat "sec-" section-number)
                                (org-element-property :ID headline))))
             (preferred-id (car ids))
             (extra-ids (cdr ids))
             (left-p (zerop (% headline-order 2))))
        (org-freeplane--build-stylized-node
         (org-freeplane--get-node-style headline info)
         (format "<node ID=\"%s\" POSITION=\"%s\" FOLDED=\"%s\">\n</node>"
                 preferred-id
                 (if left-p "left" "right")
                 (if (= level 1) "true" "false"))
         (concat (org-freeplane--build-node-contents headline contents info)
                 (org-freeplane--tags tags))))))))

;;;; Section

(defun org-freeplane-section (section contents info)
  "Transcode a SECTION element from Org to Freeplane Mindmap.
CONTENTS holds the contents of the section.  INFO is a plist
holding contextual information."
  (let ((parent (org-export-get-parent-headline section)))
    (when (and parent (org-export-low-level-p parent info))
      contents)))


;;; Filter Functions

(defun org-freeplane-final-function (contents backend info)
  "Return CONTENTS as pretty XML using `indent-region'."
  (if (not org-freeplane-pretty-output) contents
    (with-temp-buffer
      (nxml-mode)
      (insert contents)
      (indent-region (point-min) (point-max))
      (buffer-substring-no-properties (point-min) (point-max)))))

(defun org-freeplane-options-function (info backend)
  "Install script in export options when appropriate.
EXP-PLIST is a plist containing export options.  BACKEND is the
export back-end currently used."
  ;; Freeplane/Freeplane doesn't seem to like named html entities in
  ;; richcontent.  For now, turn off smart quote processing so that
  ;; entities like "&rsquo;" & friends are avoided in the exported
  ;; output.
  (plist-put info :with-smart-quotes nil))


;;; End-user functions

;;;###autoload
(defun org-freeplane-export-to-freeplane
    (&optional async subtreep visible-only body-only ext-plist)
  "Export current buffer to a Freeplane Mindmap file.

If narrowing is active in the current buffer, only export its
narrowed part.

If a region is active, export that region.

A non-nil optional argument ASYNC means the process should happen
asynchronously.  The resulting file should be accessible through
the `org-export-stack' interface.

When optional argument SUBTREEP is non-nil, export the sub-tree
at point, extracting information from the headline properties
first.

When optional argument VISIBLE-ONLY is non-nil, don't export
contents of hidden elements.

When optional argument BODY-ONLY is non-nil, only write code
between \"<body>\" and \"</body>\" tags.

EXT-PLIST, when provided, is a property list with external
parameters overriding Org default settings, but still inferior to
file-local settings.

Return output file's name."
  (interactive)
  (let* ((extension (concat ".mm"))
         (file (org-export-output-file-name extension subtreep))
         (org-export-coding-system 'utf-8))
    (org-export-to-file 'freeplane file
      async subtreep visible-only body-only ext-plist)))

(provide 'ox-freeplane)

;;; ox-freeplane.el ends here
