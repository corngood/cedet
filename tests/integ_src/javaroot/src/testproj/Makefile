# Makefile --- Build a jar file for testing.
#
# Copyright (C)  Eric M. Ludlam
#
# Author: Eric M. Ludlam <eric@siege-engine.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/.

CLASSFILES:=TestInJar.class

all: clean ../../projjar/TestProj.jar

clean:
	rm -f $(CLASSFILES)

%.class: %.java
	javac $<

../../projjar/TestProj.jar: $(CLASSFILES)
	cd ..; jar cvf ../projjar/TestProj.jar $(addprefix testproj/, $<)


# end
