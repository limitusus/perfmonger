include ../common.mk

AM_CFLAGS = -g -Wall
AM_LDFLAGS = -no-undefined

SUBDIRS = sysstat ruby

EXTRA_DIST = perfmonger.in

bin_SCRIPTS = perfmonger

noinst_LTLIBRARIES = libperfmonger.la
bin_PROGRAMS = perfmonger-record

libperfmonger_la_SOURCES = libperfmonger.c perfmonger.h
libperfmonger_la_LIBADD = ./sysstat/libsysstat.la

perfmonger_record_SOURCES = main.c
perfmonger_record_LDADD = libperfmonger.la

perfmonger: perfmonger.in Makefile
	$(edit) $< > $@.tmp
	chmod +x $@.tmp
	mv $@.tmp $@
