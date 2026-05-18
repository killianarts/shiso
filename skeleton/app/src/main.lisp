(in-package #:<% @var name %>)

(defun main ()
  (shiso:start <% @var name %>/routes:application :host "127.0.0.1" :port 5000)
  (loop (sleep 60)))
