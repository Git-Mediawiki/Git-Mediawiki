## What is Git-Mediawiki ?

Git-Mediawiki is a project which aims the creation of a gate
between git and mediawiki, allowing git users to push and pull
objects from mediawiki just as one would do with a classic git
repository thanks to remote-helpers.

**For more information, read the [User manual](docs/User-manual).**

## Who are we ?

Git-Mediawiki was essentially developed by [Ensimag](http://ensimag.grenoble-inp.fr/) students (see the logs for the detailed list of authors), supervised  by [Matthieu Moy](https://matthieu-moy.fr/), with the help of the [git community](http://git.kernel.org/).

Do not hesitate to contact us if you have any questions about the project.

Note that Git-Mediawiki is currently looking for a new maintainer, see issue [#33](https://github.com/Git-Mediawiki/Git-Mediawiki/issues/33).

## Links

* [User manual](docs/User-manual)
* [Bug tracking](https://github.com/Git-Mediawiki/Git-Mediawiki/issues)
* [Implementation documentation](docs/Implementation-documentation)
   * [Remote helpers](docs/Remote-Helpers)
   * [Fast import & Fast export](docs/Fast-Import-&-Fast-Export)
   * Storing metadata : [Git notes](docs/Git-nodes)
   * [Data-encoding](docs/Data-encoding)
* [Further Developing](docs/Further-Developing)

## Similar projects

Our project wants to be transparent to wiki users and transplantable on any wiki without having to change anything server-side. A simple git clone on a mediawiki would initialize a repository on your side and you would be able to interact with the wiki without bothering classic users.

But there are other options for archiving wikis and git-based wikis:

 * [GitHub](https://github.com/) and [ikiwiki](http://ikiwiki.info/)
   propose solutions for git-based wikis.
 * The [WikiTeam][] has scripts and programs to dump Mediawiki sites,
   although not to git, and readonly.

[WikiTeam]: https://github.com/WikiTeam/wikiteam
