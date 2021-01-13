
# We create a .mlb project file in src/, which we pass to MLton
# primarily in order to get good error checking and reporting. The
# actual build just concats the source files to produce a single
# repoint.sml file which can then be run from a script.

SOURCES	:= \
	src/version.sml \
	src/types.sml \
	src/cache.sml \
	src/filebits.sml \
	src/control.sml \
	src/sml-simplejson/json.sml \
	src/jsonbits.sml \
	src/provider.sml \
	src/hg.sml \
	src/git.sml \
	src/sml-subxml/subxml.sml \
	src/svn.sml \
	src/anycontrol.sml \
	src/archive.sml \
	src/app.sml

repoint.sml:	$(SOURCES)
	echo '$$(SML_LIB)/basis/basis.mlb' > src/repoint.mlb
	echo $(SOURCES) | sed 's,src/,,g' | fmt -1 >> src/repoint.mlb
	echo "main.sml" >> src/repoint.mlb
	mlton src/repoint.mlb
	echo "(*" > $@
	echo "    DO NOT EDIT THIS FILE." >> $@
	echo "    This file is automatically generated from the individual" >> $@
	echo "    source files in the Repoint repository." >> $@
	echo "*)" >> $@
	echo >> $@
	cat $(SOURCES) >> $@
	./repoint version

.PHONY:	test
test:	repoint.sml
	if ! ./test/run-tests.sh ; then ./test/run-tests.sh -v ; fi

.PHONY:	test-all
test-all:	repoint.sml
	if ! ./test/run-all-tests.sh ; then ./test/run-all-tests.sh -v ; fi

clean:
	rm -f repoint.sml src/repoint.mlb src/repoint

