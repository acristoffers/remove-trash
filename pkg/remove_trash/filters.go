package remove_trash

import "regexp"

// Internal state for each call to Traverse
type regexFilter struct {
	removeRegexes []*regexp.Regexp // The compiled regexes of items to remove
	ignoreRegexes []*regexp.Regexp // The compiled regexes of items to ignore
}

// Compiles the regexes that are used to decide if a file/folder is trash or
// not. It matches against basename, that is, only the file name, without path.
func (self *regexFilter) compileRegexes() error {
	removeRegexes := []string{
		`^\.DS_Store$`,
		`^\.cache$`,
		`^\.gradle$`,
		`^\.mypy_cache$`,
		`^\.sass-cache$`,
		`^\.textpadtmp$`,
		`^Thumbs.db$`,
		`^__pycache__$`,
		`^_build$`,
		`^build$`,
		`^slprj$`,
		`^zig-cache$`,
		`^zig-out$`,
		`\.slxc$`,
		`\.bak$`,
		`^~`,
	}

	ignoreRegexes := []string{
		`^\.git$`,
		`^\.var$`,
		`^Steam$`,
		`^\.steam$`,
		`^containers$`,
		`^\.dropbox-dist$`,
	}

	self.removeRegexes = make([]*regexp.Regexp, 0, len(removeRegexes))
	self.ignoreRegexes = make([]*regexp.Regexp, 0, len(removeRegexes))

	for _, regex := range removeRegexes {
		re, err := regexp.Compile(regex)
		if err != nil {
			return err
		}

		self.removeRegexes = append(self.removeRegexes, re)
	}

	for _, regex := range ignoreRegexes {
		re, err := regexp.Compile(regex)
		if err != nil {
			return err
		}

		self.ignoreRegexes = append(self.ignoreRegexes, re)
	}

	return nil
}

// Uses regex to determine if a given file name is a trash file name
func (self regexFilter) isTrash(name string) bool {
	return anyMatches(name, self.removeRegexes)
}

// Uses regex to determine if a given file/folder should be ignored
func (self regexFilter) shouldIgnore(name string) bool {
	return anyMatches(name, self.ignoreRegexes)
}

func anyMatches(item string, regexes []*regexp.Regexp) bool {
	for _, regex := range regexes {
		if regex.MatchString(item) {
			return true
		}
	}
	return false
}
