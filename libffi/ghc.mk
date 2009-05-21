# -----------------------------------------------------------------------------
#
# (c) 2009 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------


# We package libffi as Haskell package for two reasons: 

# 1) GHC uses different names for shared and static libs, so it can
#    choose the lib variant to link with on its own. With regular
#    libtool styled shared lib names, the linker would interfer and
#    link against the shared lib variant even when GHC runs in -static
#    mode.
# 2) The first issue isn't a problem when a shared lib of libffi would
#    be installed in system locations, but we do not assume that. So,
#    when running in -dynamic mode, we must either install libffi to
#    system locations ourselves, or we must add its location to
#    respective environment variable, (DY)LD_LIBRARY_PATH etc...before
#    we call dynamically linked binaries. Especially, the latter is
#    necessary as GHC calls binary it produced before its installation
#    phase. However, both mechanism, installing to system locations or
#    modifying (DY)LD_LIBRARY_PATH, are already in place for Haskell
#    packages so with packaging libffi as Haskell package we reuse
#    them naturally.

# -----------------------------------------------------------------------------
#
# We use libffi's own configuration stuff.

PLATFORM := $(shell echo $(HOSTPLATFORM) | sed 's/i[567]86/i486/g')

# 2007-09-26
#     set -o igncr 
# is not a valid command on non-Cygwin-systems.
# Let it fail silently instead of aborting the build.
#
# 2007-07-05
# We do
#     set -o igncr; export SHELLOPTS
# here as otherwise checking the size of limbs
# makes the build fall over on Cygwin. See the thread
# http://www.cygwin.com/ml/cygwin/2006-12/msg00011.html
# for more details.

# 2007-07-05
# Passing
#     as_ln_s='cp -p'
# isn't sufficient to stop cygwin using symlinks the mingw gcc can't
# follow, as it isn't used consistently. Instead we put an ln.bat in
# path that always fails.

ifeq "$(BuildSharedLibs)" "YES"
libffi_STAMP_CONFIGURE = libffi/stamp.ffi.configure-shared
libffi_STAMP_BUILD     = libffi/stamp.ffi.build-shared
else
libffi_STAMP_CONFIGURE = libffi/stamp.ffi.configure
libffi_STAMP_BUILD     = libffi/stamp.ffi.build
endif

BINDIST_STAMPS = libffi/stamp.ffi.build libfii/stamp.ffi.configure

INSTALL_HEADERS   += libffi/ffi.h
libffi_STATIC_LIB  = libffi/libffi.a
INSTALL_LIBS      += libffi/libHSffi.a libffi/HSffi.o

# We have to add the GHC version to the name of our dynamic libs, because
# they will be residing in the system location along with dynamic libs from
# other GHC installations.

libffi_HS_DYN_LIB_NAME = libHSffi$(dyn_libsuf)
libffi_HS_DYN_LIB      = libffi/$(libffi_HS_DYN_LIB_NAME)

ifeq "$(Windows)" "YES"
libffi_DYNAMIC_PROG = $(libffi_HS_DYN_LIB).a
libffi_DYNAMIC_LIBS = $(libffi_HS_DYN_LIB)
else
libffi_DYNAMIC_PROG =
libffi_DYNAMIC_LIBS = libffi/libffi.so libffi/libffi.so.5 libffi/libffi.so.5.0.7
endif

ifeq "$(BuildSharedLibs)" "YES"
libffi_EnableShared=yes
else
libffi_EnableShared=no
endif

ifeq "$(BuildSharedLibs)" "YES"
INSTALL_LIBS  += $(libffi_HS_DYN_LIB)
ifeq "$(Windows)" "YES"
INSTALL_PROGS += $(libffi_HS_DYN_LIB).a
endif
endif

# We have to fake a non-working ln for configure, so that the fallback
# option (cp -p) gets used instead.  Otherwise the libffi build system
# will use cygwin symbolic linkks which cannot be read by mingw gcc.
# The same trick is played by the GMP build in ../gmp.

ifneq "$(BINDIST)" "YES"
$(libffi_STAMP_CONFIGURE):
	$(RM) -rf $(LIBFFI_DIR) libffi/build
	cd libffi && $(TAR) -zxf tarball/libffi*.tar.gz
	mv libffi/libffi-* libffi/build
	chmod +x libffi/ln
	cd libffi && $(PATCH) -p0 < libffi.dllize-3.0.6.patch

	# This patch is just the resulting delta from running automake, autoreconf, libtoolize --force --copy
	cd libffi && $(PATCH) -p0 < libffi.autotools-update.patch

	cd libffi && \
	  (set -o igncr 2>/dev/null) && set -o igncr; export SHELLOPTS; \
	    PATH=`pwd`:$$PATH; \
	    export PATH; \
	    cd build && \
	    CC=$(WhatGccIsCalled) \
        CFLAGS="$(SRC_CC_OPTS)" \
        LDFLAGS="$(SRC_LD_OPTS)" \
        $(SHELL) configure \
	          --enable-static=yes \
	          --enable-shared=$(libffi_EnableShared) \
	          --host=$(PLATFORM) --build=$(PLATFORM)

	# libffi.so needs to be built with the correct soname.
	# NOTE: this builds libffi_convience.so with the incorrect
	# soname, but we don't need that anyway!
	cd libffi && \
	  $(CP) build/libtool build/libtool.orig; \
	  sed -e s/soname_spec=.*/soname_spec="$(libffi_HS_DYN_LIB_NAME)"/ build/libtool.orig > build/libtool

	# We don't want libtool's cygwin hacks
	cd libffi && \
	  $(CP) build/libtool build/libtool.orig; \
	  sed -e s/dlname=\'\$$tdlname\'/dlname=\'\$$dlname\'/ build/libtool.orig > build/libtool

	touch $@

libffi/ffi.h: $(libffi_STAMP_CONFIGURE)
	$(CP) libffi/build/include/ffi.h $@

$(libffi_STAMP_BUILD): $(libffi_STAMP_CONFIGURE)
	cd libffi && \
	  $(MAKE) -C build MAKEFLAGS=; \
	  (cd build; ./libtool --mode=install cp libffi.la $(TOP)/libffi)
	touch $@

$(libffi_STATIC_LIB): $(libffi_STAMP_BUILD)
# Rename libffi.a to libHSffi.a
libffi/libHSffi.a libffi/libHSffi_p.a: $(libffi_STATIC_LIB)
	$(CP) $(libffi_STATIC_LIB) libffi/libHSffi.a
	$(CP) $(libffi_STATIC_LIB) libffi/libHSffi_p.a

$(eval $(call all-target,libffi,libffi/libHSffi.a libffi/libHSffi_p.a))

# The GHCi import lib isn't needed as compiler/ghci/Linker.lhs + rts/Linker.c
# link the interpreted references to FFI to the compiled FFI.
# Instead of adding libffi to the list preloaded packages (see
# compiler/ghci/Linker.lhs:emptyPLS) we generate an empty HSffi.o

libffi/HSffi.o: libffi/libHSffi.a
	cd libffi && \
	  touch empty.c; \
	  $(CC) $(SRC_CC_OPTS) -c empty.c -o HSffi.o

$(eval $(call all-target,libffi,libffi/HSffi.o))

ifeq "$(BuildSharedLibs)" "YES"
ifeq "$(Windows)" "YES"
libffi/libffi.dll.a $(libffi_HS_DYN_LIB): $(libffi_STAMP_BUILD)
# Windows libtool creates <soname>.dll, and as we already patched that
# there is no need to copy from libffi.dll to libHSffi...dll.
# However, the renaming is still required for the import library
# libffi.dll.a.
$(libffi_HS_DYN_LIB).a: libffi/libffi.dll.a
	$(CP) libffi/libffi.dll.a $(libffi_HS_DYN_LIB).a

$(eval $(call all-target,libffi,$(libffi_HS_DYN_LIB).a))

else
$(libffi_DYNAMIC_LIBS): $(libffi_STAMP_BUILD)
# Rename libffi.so to libHSffi...so
$(libffi_HS_DYN_LIB): $(libffi_DYNAMIC_LIBS)
	$(CP) $(word 1,$(libffi_DYNAMIC_LIBS)) $(libffi_HS_DYN_LIB)

$(eval $(call all-target,libffi,$(libffi_HS_DYN_LIB)))
endif
endif

$(eval $(call clean-target,libffi,, \
   libffi/build libffi/stamp.ffi.* libffi/ffi.h libffi/empty.c \
   libffi/libffi.a libffi/libffi.la \
   libffi/HSffi.o libffi/libHSffi.a libffi/libHSffi_p.a \
   $(libffi_DYNAMIC_PROG) $(libffi_DYNAMIC_LIBS) \
   $(libffi_HS_DYN_LIB) $(libffi_HS_DYN_LIB).a))
endif

#-----------------------------------------------------------------------------
# Do the package config

$(eval $(call manual-package-config,libffi))

#-----------------------------------------------------------------------------
#
# binary-dist

BINDIST_EXTRAS += libffi/package.conf.in

