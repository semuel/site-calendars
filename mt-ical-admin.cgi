#!/usr/bin/perl -w

# Movable Type (r) (C) 2001-2013 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

use strict;
use lib $ENV{MT_HOME}
    ? "$ENV{MT_HOME}/plugins/iCalManager/lib"
    : 'plugins/iCalManager/lib';
use lib $ENV{MT_HOME}
    ? "$ENV{MT_HOME}/plugins/iCalManager/extlib"
    : 'plugins/iCalManager/extlib';
use lib $ENV{MT_HOME} ? "$ENV{MT_HOME}/lib" : 'lib';
use MT::Bootstrap App => 'ICalManager::App';
