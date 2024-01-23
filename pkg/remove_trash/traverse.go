// Package remove_trash exports the Traverse function, which traverses a path
// and removes all trash files and folders in it, reporting progress and
// calculating the size freed by the operation.
package remove_trash

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
)

// The type of the function that is called to report progress. The arguments
// are, in order, the current count, the current total and the number of bytes
// freed by this operation (that is, so far). The total can and does change
// as files are discovered.
type ProgressReport struct {
	Count uint64
	Total uint64
	Bytes uint64
}

// Internal state for each call to Traverse
type internalState struct {
	removeRegexes []*regexp.Regexp // The compiled regexes of items to remove
	ignoreRegexes []*regexp.Regexp // The compiled regexes of items to ignore
}

// Instead of throwing an error and stopping, the errors are collected and
// returned at the end. This represents files/folders which could not be deleted
// by os.RemoveAll
type FailedPath struct {
	Path string
	Err  error
}

// Compiles the regexes that are used to decide if a file/folder is trash or
// not. It matches against basename, that is, only the file name, without path.
func (self *internalState) compileRegexes() error {
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
func (self *internalState) isTrash(name string) bool {
	for _, regex := range self.removeRegexes {
		if regex.MatchString(name) {
			return true
		}
	}

	return false
}

// Uses regex to determine if a given file/folder should be ignored
func (self *internalState) shouldIgnore(name string) bool {
	for _, regex := range self.ignoreRegexes {
		if regex.MatchString(name) {
			return true
		}
	}

	return false
}

// Traverses path, returning a list of files/folders that were removed.
// If dryRun is true, do not remove any file.
// pr is called to report progress.
func Traverse(path string, dryRun bool, pr chan<- ProgressReport) ([]string, []FailedPath, error) {
  defer close(pr)

	var removedPaths []string = make([]string, 0, 1000)
	var failedPaths []FailedPath = make([]FailedPath, 0, 1000)

	homePath, err := os.UserHomeDir()
	if err != nil {
		return nil, nil, err
	}

	if strings.HasPrefix(path, "~/") {
		path = filepath.Join(homePath, path[2:])
	}

	absolutePath, err := filepath.Abs(path)
	if err != nil {
		return nil, nil, err
	}

	state := internalState{}
	if err := state.compileRegexes(); err != nil {
		return nil, nil, err
	}

	stat, err := os.Lstat(absolutePath)
	if err != nil {
		return nil, nil, err
	} else if !stat.IsDir() {
		if stat.Mode().IsRegular() && state.isTrash(absolutePath) {
			if err := os.RemoveAll(absolutePath); err != nil {
				failedPaths = append(failedPaths, FailedPath{absolutePath, err})
			} else {
				pr <- ProgressReport{1, 1, uint64(stat.Size())}
			}
			return removedPaths, failedPaths, nil
		} else {
			return removedPaths, failedPaths, nil
		}
	}

	var wg sync.WaitGroup

	var total atomic.Uint64
	var count atomic.Uint64

	total.Store(0)
	count.Store(0)

	pr <- ProgressReport{0, 1, 0}

	walkFn := func(dirPath string, d fs.DirEntry, err error) error {
		dirPathAbsolute := filepath.Join(path, dirPath)

		if err != nil {
			failedPaths = append(failedPaths, FailedPath{dirPath, err})
			if d != nil && d.IsDir() {
				return fs.SkipDir
			} else {
				return nil
			}
		}

		if state.shouldIgnore(d.Name()) {
			return fs.SkipDir
		} else if state.isTrash(d.Name()) {
			total.Add(1)
			pr <- ProgressReport{count.Load(), total.Load(), 0}

			removedPaths = append(removedPaths, dirPathAbsolute)

			worker := func() {
				defer wg.Done()

				totalSize := uint64(0)
				readSize := func(path string, file os.FileInfo, err error) error {
					if file.Mode().IsRegular() {
						totalSize += uint64(file.Size())
					}
					return nil
				}
				filepath.Walk(dirPathAbsolute, readSize)

				if dryRun {
					count.Add(1)
					pr <- ProgressReport{count.Load(), total.Load(), totalSize}
				} else {
					if err := os.RemoveAll(dirPathAbsolute); err != nil {
						failedPaths = append(failedPaths, FailedPath{dirPathAbsolute, err})
					} else {
						count.Add(1)
						pr <- ProgressReport{count.Load(), total.Load(), totalSize}
					}
				}
			}

			wg.Add(1)
			go worker()

			if d.IsDir() {
				return fs.SkipDir
			}
		}

		return nil
	}

	if err := fs.WalkDir(os.DirFS(absolutePath), ".", walkFn); err != nil {
		return nil, nil, err
	}

	wg.Wait()

	return removedPaths, failedPaths, nil
}
