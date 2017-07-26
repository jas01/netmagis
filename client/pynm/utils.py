import sys
import os
import difflib
import subprocess

#
# Show diffs (on stdout) between a file and a text
#

def diff_file_text (fname, txt):
    #
    # Read existing file as a list of strings
    #

    if os.path.exists (fname):
        with open (fname, 'r') as f:
            old = f.readlines ()
    else:
        old = []

    #
    # Convert new text into a list of strings (terminated by \n)
    #

    new = txt.splitlines (keepends=True)

    #
    # Diff contents
    #

    d = difflib.unified_diff (old, new, fromfile=fname, n=0)
    sys.stdout.writelines (d)

#
# Run a command and returns (exit code, stderr-if-exitcode-not-null)
#

def run (cmd):
    r = 0
    stderr = None
    try:
        l = ['sh', '-c', cmd]
        subprocess.check_output (l, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as err:
        r = err.returncode
        stderr = err.output
    return (r, stderr)