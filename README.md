<img width="128" alt="The Roc logo, an origami bird" src="https://user-images.githubusercontent.com/1094080/92188927-e61ebd00-ee2b-11ea-97ef-2fc88e0094b0.png">

Roc is a work in progress programming language that aims to include various great features seen in other languages and compilers.
In order for Roc to have mainstream use in the industry, one of its main focus is running fast and dynamically, which means 
Roc compiles to machine Code. The future use case for this language is to be able to build high-quality servers, command-line
applications, graphical native desktop UI, along with other classes of applications.

Current Progress
----------------

Progress toward this performance target is already well underway.
Roc already employs unboxed data structures and closures, monomorphizes polymorphic code, and employs LLVM as a compiler backend. These optimizations, particularly unboxed closures and monomorphization, can be found in a number of system-level languages (such as C++ and Rust), but not in any mainstream garbage-collected language.
Roc closures, in particular, have the advantage of being as ergonomic as garbage-collected language closures (where they are often boxed), but with the performance of systems language closures (which are typically unboxed, but have more complicated types).
As a result of these optimizations, Roc code already compiles to the same machine instructions as similar code written in one of these systems languages.
We compare the LLVM instructions generated by Roc's compiler with the compilers for these systems languages on a regular basis to see if we're generating identical instructions.
However, there are some circumstances where Roc has a higher runtime overhead than languages like as C, C++, Zig, and Rust. Automated memory management, which Roc implements with automatic reference counting, is the most expensive.
Static reference count improvements like as elision and reuse (due to Morphic and Perceus) help, but there is still significant runtime overhead.

Contributing
------------

If you're interested in getting involved, check out [CONTRIBUTING.md](https://github.com/roc-lang/roc/blob/main/CONTRIBUTING.md)!
Also for more questions and discussions please use the [Zulip][zulip-link] chat is also the best place to get help with [good first issues](https://github.com/roc-lang/roc/issues?q=is%3Aopen+is%3Aissue+label%3A%22good+first+issue%22).
If you're interested in substantial implementation- or research-heavy projects related to Roc, check out [Roc Project Ideas][project-ideas]!

# Work in progress!

Roc is not ready for a 0.1 release yet, but we do have:

- [**installation** guide](https://github.com/roc-lang/roc/tree/main/getting_started)
- [**tutorial**](https://roc-lang.org/tutorial)
- [**docs** for the standard library](https://www.roc-lang.org/builtins/Str)
- [frequently asked questions](https://github.com/roc-lang/roc/blob/main/FAQ.md)

## Sponsors

We are very grateful to our sponsors [NoRedInk](https://www.noredink.com/), [rwx](https://www.rwx.com), and [Tweede golf](https://tweedegolf.nl/en).

[<img src="https://www.noredink.com/assets/logo-red-black-f6989d7567cf90b349409137595e99c52d036d755b4403d25528e0fd83a3b084.svg" height="60" alt="NoRedInk logo"/>](https://www.noredink.com/)
&nbsp;&nbsp;&nbsp;&nbsp;
[<img src="https://www.rwx.com/build/_assets/rwx_banner_transparent_cropped-RYV7W2KL.svg" height="60" alt="rwx logo"/>](https://www.rwx.com)
&nbsp;&nbsp;&nbsp;&nbsp;
[<img src="https://user-images.githubusercontent.com/1094080/183123052-856815b1-8cc9-410a-83b0-589f03613188.svg" height="60" alt="tweede golf logo"/>](https://tweedegolf.nl/en)

If you or your employer would like to sponsor Roc's development, please [DM Richard Feldman on Zulip](https://roc.zulipchat.com/#narrow/pm-with/281383-user281383)!


[project-ideas]: https://docs.google.com/document/d/1mMaxIi7vxyUyNAUCs98d68jYj6C9Fpq4JIZRU735Kwg/edit?usp=sharing
[zulip-link]: https://roc.zulipchat.com
