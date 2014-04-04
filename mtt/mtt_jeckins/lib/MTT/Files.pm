#!/usr/bin/env perl
#
# Copyright (c) 2005-2006 The Trustees of Indiana University.
#                         All rights reserved.
# Copyright (c) 2006-2012 Cisco Systems, Inc.  All rights reserved.
# Copyright (c) 2007-2009 Sun Microsystems, Inc.  All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

package MTT::Files;

use strict;
use File::Basename;
use File::Find;
use File::Spec;
use MTT::Messages;
use MTT::DoCommand;
use MTT::FindProgram;
use MTT::Defaults;
use MTT::Values;
use MTT::Lock;
use Data::Dumper;

# How many old builds to keep
my $keep_builds = 3;

# the download program to use
my $http_agent;

#--------------------------------------------------------------------------

sub make_safe_filename {
    my ($filename) = @_;

    $filename =~ s/[ :\/\\\*\&\$\#\@\!\t]/_/g;
    return $filename;
}

sub make_safe_dirname {
    my ($ret) = @_;

    $ret = MTT::Files::make_safe_filename($ret);
    return MTT::Files::mkdir($ret);
}

#--------------------------------------------------------------------------

sub safe_mkdir {
    my ($dir) = @_;
    MTT::Files::mkdir($dir, 1);
}

#--------------------------------------------------------------------------

sub mkdir {
    my ($dir, $safe) = @_;

    my $c = MTT::DoCommand::cwd();
    Debug("Making dir: $dir (cwd: $c)\n");
    my @parts = split(/\//, $dir);

    my $str;
    if (substr($dir, 0, 1) eq "/") {
        $str = "/";
        shift(@parts);
    }

    # Test and make

    foreach my $p (@parts) {
        next if (! $p);

        $p = make_safe_filename($p)
            if ($safe);

        $str .= "$p";
        if (! -d $str) {
            Debug("$str does not exist -- creating\n");
            mkdir($str, 0777);
            if (! -d $str) {
                Abort("Could not make directory $p\n");
            }
        }
        $str .= "/";
    }

    # Return an absolute version of the created directory
    my $ret = File::Spec->rel2abs($str);

    return $ret;
} 

#--------------------------------------------------------------------------

# unpack a tarball in the cwd and figure out what directory it
# unpacked into
sub unpack_tarball {
    my ($tarball, $delete_first) = @_;

    Debug("Unpacking tarball: $tarball\n");

    if (! -f $tarball) {
        Warning("Tarball does not exist: $tarball\n");
        return undef;
    }

    # Decide which unpacker to use

    my $unpacker;
    if ($tarball =~ /.*\.t?bz2?$/) {
        $unpacker="bunzip2";
    } elsif ($tarball =~ /.*\.t?gz$/) {
        $unpacker="gunzip";
    } else {
        Warning("Unrecognized tarball extension ($tarball); don't know how to uncompress -- skipped\n");
        return undef;
    }

    # Examine the tarball and see what it puts in the cwd

    open(TAR, "$unpacker -c $tarball | tar tf - |");
    my @entries = <TAR>;
    close(TAR);
    my $dirs;
    my $files;
    foreach my $e (@entries) {
        chomp($e);
        # If no /'s, then it's possibly a file in the top-level dir --
        # save for later analysis.
        if ($e !~ /\//) {
            $files->{$e} = 1;
        } else {
            # If there's a / anywhere in the name, then save the
            # top-level dir name
            $e =~ s/(.+?)\/.*/\1/;
            $dirs->{$e} = 1;
        }
    }

    # Check all the "files" and ensure that they weren't just entries
    # in the tarball to make a directory (this shouldn't happen, but
    # just in case...)

    foreach my $f (keys(%$files)) {
        if (exists($dirs->{$f})) {
            delete $files->{$f};
        }
    }

    # Any top-level files left?

    my $tarball_dir;
    if (keys(%$files)) {
        my $b = basename($tarball);
        Debug("GOT FILES IN TARBALL\n");
        $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
        MTT::DoCommand::Chdir($tarball_dir);
    } else {
        my @k = keys(%$dirs);
        if ($#k != 0) {
            my $b = basename($tarball);
            Debug("GOT MULTI DIRS IN TARBALL\n");
            print Dumper($dirs);
            $tarball_dir = MTT::Files::mkdir("slimy_tarball_$b");
            MTT::DoCommand::Chdir($tarball_dir);
        } else {
            $tarball_dir = $k[0];
        }
    }
    Debug("Tarball dir is: $tarball_dir\n");

    # Remove the tree first if requested
    MTT::DoCommand::Cmd(1, "rm -rf $tarball_dir")
        if ($delete_first);

    # Untar the tarball.  Do not use DoCommand here
    # because we don't want the result_stdout intercepted.

    system("$unpacker -c $tarball | tar xf -");
    my $ret = $? >> 8;
    if ($ret != 0) {
        Warning("Failed to unpack tarball successfully: $tarball: $@\n");
        return undef;
    }
    
    return $tarball_dir;
}

#--------------------------------------------------------------------------

sub copy_tree {
    my ($srcdir, $delete_first) = @_;

    Debug("Copying directory: $srcdir\n");

    # Remove trailing slash
    $srcdir =~ s/\/\s*$//;

    if (! -d $srcdir) {
        Warning("Directory does not exist: $srcdir\n");
        return undef;
    }

    my $b = basename($srcdir);
    MTT::DoCommand::Cmd(1, "rm -rf $b")
        if ($delete_first);

    my $ret = MTT::DoCommand::Cmd(1, "cp -r $srcdir .");
    if (!MTT::DoCommand::wsuccess($ret->{exit_status})) {
        Warning("Could not copy file tree $srcdir: $!\n");
        return undef;
    }

    return $b;
}

#--------------------------------------------------------------------------

my $md5sum_path;
my $md5sum_searched;

sub _find_md5sum {
    # Search
    $md5sum_path = FindProgram(qw(md5sum gmd5sum));
    $md5sum_searched = 1;
    if (!$md5sum_path) {
        Warning("Could not find md5sum executable, so I will not be able to check the validity of downloaded executables against their known MD5 checksums.  Proceeding anyway...\n");
    }
}

sub md5sum {
    my ($file) = @_;

    _find_md5sum()
        if (!$md5sum_searched);
    # If we already searched and didn't find it, then just return undef
    return undef
        if (!$md5sum_path && $md5sum_searched);
    return undef
        if (! -f $file);

    my $x = MTT::DoCommand::Cmd(1, "$md5sum_path $file");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("md5sum unable to run properly\n");
        return undef;
    }
    $x->{result_stdout} =~ m/^\s*(\w{32})/;
    return $1;
}

#--------------------------------------------------------------------------

my $sha1sum_path;
my $sha1sum_searched;

sub sha1sum {
    my ($file) = @_;

    # Setup if we haven't already
    if (!$sha1sum_path) {
        # If we already searched and didn't find it, then just return undef
        return undef
            if ($sha1sum_searched);

        # Search
        $sha1sum_path = FindProgram(qw(sha1sum gsha1sum));
        $sha1sum_searched = 1;
        if (!$sha1sum_path) {
            Warning("Could not find sha1sum executable, so I will not be able to check the validity of downloaded executables against their known SHA1 checksums.  Proceeding anyway...\n");
            return undef;
        }
    }

    my $x = MTT::DoCommand::Cmd(1, "$sha1sum_path $file");
    if (!MTT::DoCommand::wsuccess($x->{exit_status})) {
        Warning("sha1sum unable to run properly\n");
        return undef;
    }
    $x->{result_stdout} =~ m/^\s*(\w{40})/;
    return $1;
}

#--------------------------------------------------------------------------

my $mtime_max;

sub _do_mtime {
    # don't process special directories or links, and dont' recurse
    # down "special" directories
    if ( -l $_ ) { return; }
    if ( -d $_  && 
         ((/\.svn/) || (/\.deps/) || (/\.libs/))) {
        $File::Find::prune = 1;
        return;
    }

    # $File::Find::name is the path relative to the starting point.
    # $_ contains the file's basename.  The code automatically changes
    # to the processed directory, so we want to open / close $_.
    my @stat_info = stat($_);
    $mtime_max = $stat_info[9]
        if ($stat_info[9] > $mtime_max);
}

sub mtime_tree {
    my ($dir) = @_;

    $mtime_max = -1;
    find(\&_do_mtime, $dir);

    return $mtime_max;
}

#--------------------------------------------------------------------------

sub http_get {
    my ($url, $username, $password) = @_;

    my $scheme;
    if ($url =~ /^http:\/\//) {
        $scheme = "http";
    } elsif ($url =~ /^https:\/\//) {
        $scheme = "https";
    } elsif ($url =~ /^ftp:\/\//) {
        $scheme = "ftp";
    }

    # figure out what download command to use
    if (!$http_agent) {
        foreach my $agent (keys(%{$MTT::Defaults::System_config->{http_agents}})) {
            my $found = FindProgram($agent);
            if ($found) {
                $http_agent = $MTT::Defaults::System_config->{http_agents}->{$agent};
                last;
            }
        }
    }
    Abort("Cannot find downloading program -- aborting in despair\n")
        if (!defined($http_agent));
    my $outfile = basename($url);

    # Loop over proxies
    my $proxies = \@{$MTT::Globals::Values->{proxies}->{$scheme}};
    my %ENV_SAVE = %ENV;
    foreach my $p (@{$proxies}) {
        foreach my $c (@{$http_agent->{command}}) {
            my $cmd;

            # Setup the proxy in the environment
            if ("" ne $p->{proxy}) {
                Debug("Using $scheme proxy: $p->{proxy}\n");
                $ENV{$scheme . "_proxy"} = $p->{proxy};
            }

            my $str = "\$cmd = \"" . $c;
            if (defined($username) && defined($password)) {
                $str .= " " . $http_agent->{auth};
            }
            $str .= "\"";
            eval $str;
            my $x = MTT::DoCommand::Cmd(1, $cmd);

            # Restore the environment
            %ENV = %ENV_SAVE;

            # If it succeeded, return happiness
            # (Some programs, e.g., wget, can actually exit 0 *and* fail to get
            # the file! Make sure we successfully downloaded what we need.)
            return 1
                if (MTT::DoCommand::wsuccess($x->{exit_status}) and (-e $outfile));
        }
    }

    # Failure
    return undef;
}

#--------------------------------------------------------------------------

# Copy infile or stdin to a unique file in /tmp
sub copyfile {

    my($infile) = @_;
    my($opener);
    my($outfile) = "/tmp/" . MTT::Values::RandomString(10) . ".ini";

    # stdin
    if (ref($infile) =~ /glob/i) {
        $infile = "stdin";
        $opener = "-";
    }
    # file
    else {
        $opener = "< $infile";
    }
    open(in, $opener);
    open(out, "> $outfile") or warn "Could not open $outfile for writing";

    Debug("Copying: $infile to $outfile\n");

    while (<in>) {
        print out;
    }
    close(in);
    close(out);

    return $outfile;
}

#--------------------------------------------------------------------------

sub load_dumpfile {
    my ($filename, $data) = @_;

    # Check that the file is there
    return
        if (! -r $filename);

    # Get the file size
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
        $atime, $mtime, $ctime, $blksize, $blocks) = stat($filename);

    # Read it in
    open IN, $filename;
    my $tmp;
    read(IN, $tmp, $size);
    close IN;
    
    # It's in Dumper format.  How many $VARx's are there?
    return
        if (! $tmp =~ m/\$VAR[0-9]+/g);
    my $count = 0;
    ++$count
        while ($tmp =~ m/\$VAR[0-9]+/g);

    # We know how many $VARx's there are.  Build up a string to eval.
    my $str;
    my $var_num = 1;
    while ($var_num <= $count) {
        $str .= "my \$VAR$var_num;\n";
        ++$var_num;
    }
    $str .= "eval \$tmp;\n";
    my $var_num = 1;
    while ($var_num <= $count) {
        $str .= "\$\$data->{VAR$var_num} = \$VAR$var_num;\n";
        ++$var_num;
    }
    eval $str;
}

#--------------------------------------------------------------------------

our $local_debug = 0;

sub load_dumpfiles {
    my $unique_depth = shift;
    my @files = @_;

    my $all = undef;
    my $i = 1;
    foreach my $f (@files) {
        # If the file exists, read it in
        my $data = undef;
        Debug("Loading dump file $i: $f\n");
        ++$i;

        load_dumpfile($f, \$data);

        # Skip the "VAR1" key -- all dump files have that at the top.
        $data = $data->{VAR1}
            if (exists($data->{VAR1}));
        if ($local_debug) {
            Debug("READ IN FILE: ");
            DebugDump($data);
        }

        # These dump files are structured to have the "interesting"
        # data several keys deep.  That is, there will be several
        # "outer" keys before any real data is stored in a hash.  For
        # example: $foo->{bar}->{baz}->...real_data...  The "outer"
        # keys are defines as having exactly one sub key.  The file
        # that was just read in must have a unique queue in the target
        # hash at the specific depth $unique_depth.  If we don't have
        # a unique key there, Badness has happened.  However, keys
        # above this depth may well be non-unique.
        if (defined($all)) {
            _merge_hash($f, $unique_depth - 1, \$all, \$data);
        } else {
            $all = $data;
        }
    }

    $all;
}

sub _merge_hash {
    my ($file, $depth, $a, $b) = @_;

    if ($local_debug) {
        Debug("=========================================\n");
        Debug("MERGING: depth=$depth\n");
        Debug("a = ");
        DebugDump($$a);
        Debug("-----------------------------------------\n");
        Debug("b = ");
        DebugDump($$b);
        Debug("-----------------------------------------\n");
    }

    # If our depth is < 0, we don't care about uniqueness, so just copy
    if ($depth < 0) {
        $$a = $$b;
    }

    # Otherwise, we need to examine individual keys.
    else {
        # This function is only ever called with 2 hashes, so we know
        # we can traverse keys of both $a and $b.
        foreach my $k (keys(%{$$b})) {
            Debug("Got key: $k\n")
                if ($local_debug);
            # Key collision!
            if (exists(${$a}->{$k})) {
                Debug("Collision\n")
                    if ($local_debug);

                # If we're at 0 depth, then this is the level where
                # uniqueness matters -- so error out because we got a
                # collision.
                if (0 == $depth) {
                    Error("An identical key already exists in memory when MTT tried to read the file $file (key=$k).  This should not happen.  It likely indicates that multiple MTT clients are incorrectly operating in the same scratch tree.");
                }

                # Otherwise we try to copy.  If both are hashes, recurse.
                if (ref(${$a}->{$k}) =~ /hash/i && 
                    ref(${$b}->{$k}) =~ /hash/i) {
                    _merge_hash($file, $depth - 1, \${$a}->{$k}, \${$b}->{$k});
                }
                # Otherwise, $a wins
            } 

            # No collision, so just copy $b->{$k} over
            else {
                Debug("No collision\n")
                    if ($local_debug);
                ${$a}->{$k} = ${$b}->{$k};
            }
        }
    }

    if ($local_debug) {
        Debug("MERGED: depth=$depth\n");
        DebugDump($a);
        Debug("-----------------------------------------\n");
    }
}

#--------------------------------------------------------------------------

sub save_dumpfile {
    my ($filename) = @_;
    shift;

    # Serialize
    my $d = new Data::Dumper([@_]);
    $d->Purity(1)->Indent(1);

    open FILE, ">$filename.new";
    print FILE $d->Dump;
    close FILE;

    # Atomically move it onto the old file
    rename("$filename.new", $filename);
}

# Write out a file
sub SafeWrite {
    my ($force, $filename, $body, $redir) = @_;
    my $ret;

    # Allow for various redirections, e.g., ">", ">>", etc.
    # Default to ">"
    if (! defined($redir)) {
        $redir = ">";
    }

    $ret->{success} = 0;

    # Does the file already exist?
    if (-r $filename && !$force) {
        $ret->{result_message} = "File already exists: $filename";
        return $ret;
    }

    # Write out the file
    if (!open FILE, "$redir $filename") {
        $ret->{result_message} = "Failed to write to file: $!";
        return $ret;
    }
    print FILE $body;
    close FILE;

    # All done
    $ret->{success} = 1;

    return $ret;
}

# Return the contents of a file as a scalar
sub Slurp {
    my ($file) = @_;

    my $contents;
    open (INPUT, $file) || warn "can't open $file: $!";
    while (<INPUT>) {
        $contents .= $_;
    }
    close(INPUT) || warn "can't close $file: $!";
    return $contents;
}

# Grep the contents of a file
sub Grep {
    my ($pattern, $file) = @_;

    my @contents;
    open (INPUT, $file) || warn "can't open $file: $!";
    while (<INPUT>) {
        push(@contents, $_);
    }
    close(INPUT) || warn "can't close $file: $!";

    my @ret = grep (/$pattern/, @contents);
    return \@ret;
}

# Does the equivalent of "find $dir -name $name"
sub FindName {
    my ($dir, $name) = @_;

    my @ret;
    &File::Find::find(
        sub { 
            push(@ret, $File::Find::name) if ($_ =~ /\b$name\b.?$/); 
        }, 
        $dir);

    return @ret;
}

#--------------------------------------------------------------------------

sub save_fast_scratch_files {
    my ($fast_root, $save_root) = @_;

    if (exists($MTT::Globals::Values->{save_fast_scratch_files}) &&
        defined($MTT::Globals::Values->{save_fast_scratch_files})) {
        my @target_files = 
            MTT::Util::split_comma_list($MTT::Globals::Values->{save_fast_scratch_files});
        

        # Scan the fast scratch tree fo find all filenames that we
        # care about
        Debug("Scanning fast scratch for files to save: $fast_root ($MTT::Globals::Values->{save_fast_scratch_files})\n");
        my @save_files;
        &File::Find::find(
            sub { 
                foreach my $f (@target_files) {
                    if ($_ =~ /$f/) {
                        push(@save_files, $File::Find::name);
                        last;
                    }
                }
            },
                          $fast_root);

        Debug("Saving files from fast scratch to persistent scratch...\n");
        # Save the found files in the persistent scratch.  Use the
        # same directory structure in the persistent scratch as we
        # have in the fast scratch so that we don't have problems with
        # multiple files of the same basename overwriting each other.
        foreach my $f (@save_files) {
            my $base = basename($f);
            my $dir = dirname($f);

            my $target_dir = $dir;
            $target_dir =~ s/$fast_root//;
            $target_dir = "$save_root/$target_dir";

            MTT::Files::mkdir($target_dir)
                if (! -d $target_dir);
            system("cp $f $target_dir");
        }
    }
}

1;
