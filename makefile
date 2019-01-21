#-------------------------------------------------------------------------------------------
# This makefile will download packages for, configure, build and install a GCC cross-compiler,
# and compile a kernel and busybox.
# Customize the variables to your liking before running.
# The toolchain build is based on http://preshing.com/20141119/how-to-build-a-gcc-cross-compiler
# The busybox and Kernel build are based on https://github.com/bradfa/clfs-embedded
# The ramdisk creation is based on https://www.ibm.com/developerworks/library/l-initrd/index.html  
#-------------------------------------------------------------------------------------------
#
# 	TODO:
#       See ramDisk.sh for additional todo list
#	Resources
#		http://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/
#		https://gcc.gnu.org/wiki/InstallingGCC
#		https://github.com/bradfa/clfs-embedded
#		https://www.ibm.com/developerworks/library/l-initrd/index.html
#		https://busybox.net/FAQ.html#build
#		https://wiki.osdev.org/GCC_Cross-Compiler#Using_the_new_Compiler
#		https://gcc.gnu.org/onlinedocs/libstdc++/manual/configure.html

.ONESHELL:

# Source Versions
binVer=2.27
kerVer=4.4.21
gccVer=5.4.0
libVer=2.20
bbVer=1.24.2

# WorkSpace
WORKSPACE=/opt/preshing
SRCDIR=$(WORKSPACE)/src
BUILDDIR=$(WORKSPACE)/build
PROJECT=versatileab
INSTALLDIR=$(WORKSPACE)/$(PROJECT)
SYSROOTDIR=$(INSTALLDIR)/sysroot    
RFS=$(WORKSPACE)/rfs/$(PROJECT)

#   Host environment
PARALLEL=-j4
BUILDMACH=i686-pc-linux-gnu
HOSTMACH=x86_64-pc-linux-gnu

#   Target Environment
TARGETMACH=arm-none-linux-gnueabi
TARGETARCH=arm
KCONFIG=versatile_defconfig
MACH=versatileab

# Prep 0 - prereqs
prereqs:
	sudo apt-get update
	sudo apt install -y build-essential gawk
	sudo apt install -y qemu-system-arm qemu-user-static xterm			# prerequisites for milestones

# Prep 1 - Organize workspace
workSpace:
	sudo mkdir -pv $(WORKSPACE)
	sudo chown $(USER):$(USER) -R $(WORKSPACE)
	mkdir -pv $(SRCDIR)
	mkdir -pv $(BUILDDIR)
	mkdir -pv $(INSTALLDIR)
	mkdir -pv $(SYSROOTDIR)
	mkdir -pv $(RFS)

# Prep 2 - Get source files
getSRC:
	wget -nc -P $(SRCDIR) ftp.gnu.org/gnu/binutils/binutils-$(binVer).tar.bz2
	wget -nc -P $(SRCDIR) https://www.kernel.org/pub/linux/kernel/v4.x/linux-$(kerVer).tar.xz
	wget -nc -P $(SRCDIR) ftp://gcc.gnu.org/pub/gcc/releases/gcc-$(gccVer)/gcc-$(gccVer).tar.bz2
	wget -nc -P $(SRCDIR) https://ftp.gnu.org/gnu/glibc/glibc-$(libVer).tar.xz
	wget -nc -P $(SRCDIR) http://busybox.net/downloads/busybox-$(bbVer).tar.bz2
	
# Step 1. Binutils	
binutils:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	[ -d $(BUILDDIR)/binutils-build ] && rm -rf $(BUILDDIR)/binutils-build
	mkdir $(BUILDDIR)/binutils-build
	tar -xjf $(SRCDIR)/binutils-$(binVer).tar.bz2 -C $(BUILDDIR)
	cd $(BUILDDIR)/binutils-build
	../binutils-$(binVer)/configure \
		--target=$(TARGETMACH) \
		--prefix=$(INSTALLDIR) \
		--disable-multilib 
	make $(PARALLEL)
	make install		

# Step 2. Linux Kernel Headers 
kernelHeaders:
	[ -d $(BUILDDIR)/linux-$(kerVer) ] || tar -Jxf $(SRCDIR)/linux-$(kerVer).tar.xz -C $(BUILDDIR)
	cd $(BUILDDIR)/linux-$(kerVer)
	make mrproper
	make ARCH=$(TARGETARCH) headers_check
	make ARCH=$(TARGETARCH) \
	INSTALL_HDR_PATH=$(INSTALLDIR)/$(TARGETMACH) \
	headers_install

# Step 3. C/C++ Compilers
gccStatic:	
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	[ -d $(BUILDDIR)/gcc-build ] && rm -rf $(BUILDDIR)/gcc-build
	mkdir $(BUILDDIR)/gcc-build
	tar -xjf $(SRCDIR)/gcc-$(gccVer).tar.bz2 -C $(BUILDDIR)
	cd $(BUILDDIR)/gcc-$(gccVer)
	./contrib/download_prerequisites
	cd $(BUILDDIR)/gcc-build
	../gcc-$(gccVer)/configure \
	--target=$(TARGETMACH) \
	--prefix=$(INSTALLDIR) \
	--enable-languages=c,c++ \
	--disable-multilib
	make $(PARALLEL) all-gcc 
	make install-gcc
	
# Step 4. Standard C Library Headers and Startup Files
glibcHeader:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	[ -d $(BUILDDIR)/glibc-build ] && rm -rf $(BUILDDIR)/glibc-build
	mkdir $(BUILDDIR)/glibc-build
	tar -xf $(SRCDIR)/glibc-$(libVer).tar.xz -C $(BUILDDIR)
	cd $(BUILDDIR)/glibc-build
	../glibc-$(libVer)/configure \
	--prefix=$(INSTALLDIR)/$(TARGETMACH) \
	--build=$(BUILDMACH) \
	--host=$(TARGETMACH)  \
	--target=$(TARGETMACH) \
	--with-headers=$(INSTALLDIR)/$(TARGETMACH)/include \
	--disable-multilib \
	libc_cv_forced_unwind=yes
	make install-bootstrap-headers=yes install-headers
	make $(PARALLEL) csu/subdir_lib
	install csu/crt1.o csu/crti.o csu/crtn.o $(INSTALLDIR)/$(TARGETMACH)/lib
	$(TARGETMACH)-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $(INSTALLDIR)/$(TARGETMACH)/lib/libc.so
	touch $(INSTALLDIR)/$(TARGETMACH)/include/gnu/stubs.h	

# Step 5. Compiler Support Library
gccCSL:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	cd $(BUILDDIR)/gcc-build
	make $(PARALLEL) all-target-libgcc
	make install-target-libgcc	

# Step 6. Standard C Library & the rest of Glibc
glibc:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	cd $(BUILDDIR)/glibc-build
	make $(PARALLEL) 
	make install

# Step 7. Standard C++ Library & the rest of GCC    	
gccAll:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	cd $(BUILDDIR)/gcc-build
	make $(PARALLEL) all
	make install

# Milestone Compile simple program
# Expected results: program compiles.
helloWorld:
	cat <<EOF > helloworld.c
	#include <stdio.h>
	int main()
	{
	// printf() displays the string inside quotation
	printf("Hello, World!");
	return 0;
	}
	EOF
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	$(TARGETMACH)-gcc -static helloworld.c
	readelf -h a.out

# Step 8. Compile Linux Kernel
kernel:
	[ -d $(BUILDDIR)/linux-$(kerVer) ] || tar -Jxf $(SRCDIR)/linux-$(kerVer).tar.xz -C ${BUILDDIR}
	cd $(BUILDDIR)/linux-$(kerVer)
	make mrproper
	make ARCH=$(TARGETARCH) $(KCONFIG)
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	make zImage ARCH=$(TARGETARCH) CROSS_COMPILE=$(TARGETMACH)-

# Milestone Launch kernel and blank ramdisk
# Expected results: Should see "Uncompressing Linux... done, booting the kernel.
# Kernel panic
kernelCheck:
	xterm -e 'qemu-system-arm -machine versatileab  -kernel $(BUILDDIR)/linux-$(kerVer)/arch/arm/boot/zImage   -initrd $(BUILDDIR)/linux-$(kerVer)/usr/initramfs_data.cpio.gz  -append "root=/dev/ram0 "' 
	
#Step 9.	Compile BusyBox
busyBox:
	export PATH=$(INSTALLDIR)/bin:$(PATH)
	[ -d $(BUILDDIR)/busybox-$(bbVer) ] || tar -xjf $(SRCDIR)/busybox-$(bbVer).tar.bz2 -C ${BUILDDIR}
	cd $(BUILDDIR)/busybox-$(bbVer)
	make distclean
	make ARCH=$(TARGETCH) CROSS_COMPILE=$(TARGETMACH)- defconfig
	#make ARCH=$(TARGETCH) CROSS_COMPILE=$(TARGETMACH)- menuconfig
	sed -i "/CONFIG_STATIC/s/.*/CONFIG_STATIC=y/" .config
	sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
	sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
	sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
	make ARCH=$(TARGETCH) CROSS_COMPILE=$(TARGETMACH)- 
	make ARCH=$(TARGETCH) CROSS_COMPILE=$(TARGETMACH)- install CONFIG_PREFIX=$(RFS)
	cp examples/depmod.pl $(INSTALLDIR)/bin
	chmod 755 $(INSTALLDIR)/bin/depmod.pl

# Milestone .   Launch busybox in a cross-chroot
# Expected results. One gets a command prompt.	
chrootBusyBox:
	cp	/usr/bin/qemu-$(TARGETARCH)-static $(RFS)/usr/bin/qemu-$(TARGETARCH)-static
	sudo chroot $(RFS) /bin/ash
	rm 	$(RFS)/usr/bin/qemu-$(TARGETARCH)-static

# Milestone	Launch System	
# Expected results: System boots and one recieves a command prompt.
checkSystem:
	sudo ./ramDisk.sh $(RFS) 
	qemu-system-$(TARGETARCH) -M $(MACH)  -kernel $(BUILDDIR)/linux-$(kerVer)/arch/arm/boot/zImage \
	-initrd /tmp/ramdisk.img.gz -append "root=/dev/ram0 init=/linuxrc"
	
cleanBuild:
	rm -rd $(BUILDDIR)/*	

