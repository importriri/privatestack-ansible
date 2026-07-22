;;; early-init.el --- privatestack dev_ide brick -*- lexical-binding: t -*-
(setq gc-cons-threshold (* 64 1024 1024))
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq inhibit-startup-screen t
      frame-resize-pixelwise t)
