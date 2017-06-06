
Vext
====

A simple manager for third-party source code dependencies.

Vext is a program that manages a single directory in your repository,
containing checkouts of the external source code repositories that are
needed to build your own program.

You might think of it as an alternative to Mercurial subrepositories
or Git submodules, but with less magic and with equal support for both
Mercurial and Git.

You configure Vext with a list of libraries, their remote repository
locations, and any branch or tag information you want checkouts to
follow. This list is stored in your repository, and when you run the
Vext utility, it reviews the list and checks out the necessary code.

Vext has four limitations that distinguish it from all of the "proper"
package managers like npm or Maven:

 1. It only knows how to check out library code from hosted version
 control repositories (like Github or Bitbucket). There is no support
 for installing pre-packaged or pre-compiled dependencies. If it's not
 in a repository, or if cloning the repository would be too expensive,
 then Vext won't help.  (A corollary is that you should only use Vext
 for development trees that are themselves checked out from a hosted
 repo; don't distribute source releases or end-user packages that
 depend on it. If your code is distributed via a "proper" package
 manager itself, use that package manager for its dependencies too.)

 2. It puts all third-party libraries into a subdirectory of the
 project directory. There is no per-user or system-wide package
 installation location. Every local working copy gets its own copy.

 3. It doesn't do dependency tracking. If an external library has its
 own dependencies, you have to be aware of those and add them to the
 configuration yourself.

 4. It doesn't know how to build anything. It just brings in the
 source code, and your build process is assumed to know what to do
 with it. This also means it doesn't care what language the source
 code is in.

Besides those limitations, it has one big advantage:

 1. It's equivalent to just checking out a bunch of repositories
 yourself, but with a neater interface. That makes it unintrusive and
 easy to understand, and suitable for situations where there isn't
 really a package manager that will do the job.

Vext was originally intended for use with projects written in C++,
having in the range of 1-20 library dependencies to a project.


Configuration
=============

Libraries are listed in a vext-project.json file in the top-level
working-copy directory.

An example vext-project.json:

```
{
    "config": {
        "extdir": "ext"
    },
    "libs": {
        "vamp-plugin-sdk": {
            "vcs": "git",
            "service": "github",
            "owner": "c4dm"
        },
        "bqvec": {
            "vcs": "hg",
	    "service": "bitbucket",
            "owner": "breakfastquay"
        }
    }
}
```

All libraries will be checked out into subdirectories of a single
external-library directory in the project root; the name of this
directory (typically "ext") is configured in vext-project.json. The
ext directory should normally be excluded from your project's version
control, i.e. added to your .hgignore, .gitignore etc file.

Libraries are listed in the "libs" object in the config file. Each
library has a key, which is the local name (a single directory or
relative path) it will be checked out to. Properties of the library
may include

 * vcs - The version control system to use. Must be one of the
   recognised set of names, currently "hg" or "git"

 * service - The repository hosting provider. Some providers are
   built-in, but you can define further ones in a "providers" section

 * owner - User name owning the repository at the provider

 * repository - Repository name at the provider, if it differs from
   the local library name

 * url - Complete URL to check out (alternative to specifying
   provider, owner, etc)

 * branch - Branch to check out if not the default

 * pin - Specific revision id or tag to check out
 
You can also optionally have a config file ~/.vext.json in which you
can configure things like login names to use for ssh access to
providers.

A library may be listed as either pinned (having a pin property) or
unpinned (lacking one). A pinned library has a specific tag or
revision ID associated with it, and once it has been checked out at
that tag, it won't be changed by Vext again unless the specification
for it changes. An unpinned library floats on a branch and is
potentially updated every time "vext update" is run.

Vext also creates a file called vext-lock.json, each time you update,
which stores the versions actually used in the current project
directory. This is referred to by the command "vext install" which
installs exactly those versions. You can check this file into your
version control system if you want to enable other users to get
exactly the same revisions by running "vext install" themselves.


Querying library status
=======================

Run "vext review" to check and print statuses of all the configured
libraries. This won't change the local working copies, but it does
involve contacting remote repositories to find out whether they have
been updated, so network access is required.

Run "vext status" to do the same thing but without using the
network. That's much faster but can only tell you whether something is
in place for each library, not whether it's the newest thing
available.

The statuses that may be reported are:

For unpinned libraries:

 * _Absent_: No repository has been checked out for the library yet

 * _Correct_: Library is the newest version available on the correct
   branch. If you run "vext status" instead "vext review", this will
   appear as _Present_ instead of _Correct_, as the program can't be
   sure you have the latest version without using the network.

 * _Superseded_: Library exists and is on the correct branch, but
   there is a newer revision available.

 * _Wrong_: Library exists but is checked out on the wrong branch.

For pinned libraries:

 * _Absent_: No repository has been checked out for the library yet

 * _Correct_: Library is checked out at the pinned revision.

 * _Wrong_: Library is checked out at any other revision.

Also, both pinned and unpinned libraries can be shown with a local
status either "Clean" (not changed locally) or "Modified" (someone has
made a change to the local working copy for that library).


Installing and updating
=======================

Run "vext install" to update all the configured libraries. If there is
a vext-lock.json file present, "vext install" will update all
libraries listed in that file to the precise revisions recorded there.

Run "vext update" to update all the configured libraries according to
the vext-project.json specification, regardless of the existence of
any vext-lock.json file, and then write out a new vext-lock.json
containing the resulting state. Pinned libraries will be updated if
they are in Absent or Wrong state; unpinned libraries will always be
updated, which should have an effect only when they are in Absent,
Superseded, or Wrong state.

[![Build Status](https://travis-ci.org/cannam/vext.svg?branch=master)](https://travis-ci.org/cannam/vext)


to add:

 + unify "service"/"provider" nomenclature above and in project file syntax
 + archive command
 + note about not handling libraries having their own dependencies
 + ability to commit and/or push?
 + dry-run option (print commands)?
 + more tests: service definitions, weird lib paths, explicit URL etc
