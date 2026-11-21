;;; (schevana base) — the basics every layer has, src/base.ss's: one
;;; library where the top level loads a copy into each environment. What
;;; that file has for the top level alone (its defvar, its define-exports,
;;; its live-name) stays inside: a library's are (schevana layer)'s.

(library (schevana base)
  (export clamp string-split string-join string-prefix? string-suffix?
          filter-map string-contains-ci? plist-ref plist-keys
          condition->string list-index registry-add
          platform-os platform-linux? platform-mac? platform-windows?
          platform-cpu platform-x86-64? platform-arm64?
          at-load forwarder-to forwarder-settable exports-install!
          exports-names)
  (import (chezscheme) (only (schevana layer) include-sources))

  (module (clamp string-split string-join string-prefix? string-suffix?
           filter-map string-contains-ci? plist-ref plist-keys
           condition->string list-index registry-add
           platform-os platform-linux? platform-mac? platform-windows?
           platform-cpu platform-x86-64? platform-arm64?
           at-load forwarder-to forwarder-settable exports-install!
           exports-names)
    (include-sources "src/base.ss")))
