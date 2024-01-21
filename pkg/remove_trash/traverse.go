package remove_trash

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync/atomic"

	"golang.org/x/sync/errgroup"
)

type ProgressReport func(uint64, uint64, uint64)

type InternalState struct {
	regexes []*regexp.Regexp
	removed []string
}

type FailedPath struct {
	Path string
	Err  error
}

func (self *InternalState) compileRegexes() error {
	self.regexes = []*regexp.Regexp{}
	regexes := []string{
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

	for _, regex := range regexes {
		re, err := regexp.Compile(regex)
		if err != nil {
			return err
		}

		self.regexes = append(self.regexes, re)
	}

	return nil
}

// Uses regex to determine if a given file name is a trash file name
func (self *InternalState) isTrash(name string) bool {
	for _, regex := range self.regexes {
		if regex.MatchString(name) {
			return true
		}
	}

	return false
}

// Traverses path, returning a list of files/folders that were removed.
// If dryRun is true, do not remove any file.
func Traverse(path string, dryRun bool, pr ProgressReport) ([]string, []FailedPath, error) {
	removedPaths := []string{}
	failedPaths := []FailedPath{}

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

	state := InternalState{}
	if err := state.compileRegexes(); err != nil {
		return nil, nil, err
	}

	g := new(errgroup.Group)

	var total atomic.Uint64
	var count atomic.Uint64

	total.Store(0)
	count.Store(0)

	pr(0, 1, 0)

	walkFn := func(dirPath string, d fs.DirEntry, err error) error {
		dirPathAbsolute := filepath.Join(path, dirPath)

		if err != nil {
			failedPaths = append(failedPaths, FailedPath{dirPath, err})
			if d.IsDir() {
				return fs.SkipDir
			} else {
				return nil
			}
		}

		if state.isTrash(d.Name()) {
			total.Add(1)
			pr(count.Load(), total.Load(), 0)

			removedPaths = append(removedPaths, dirPathAbsolute)

			g.Go(func() error {
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
					pr(count.Load(), total.Load(), totalSize)
				} else {
					if err := os.RemoveAll(dirPathAbsolute); err != nil {
						failedPaths = append(failedPaths, FailedPath{dirPathAbsolute, err})
					} else {
						count.Add(1)
						pr(count.Load(), total.Load(), totalSize)
					}
				}

				return nil
			})

			if d.IsDir() {
				return fs.SkipDir
			}
		}

		return nil
	}

	if err := fs.WalkDir(os.DirFS(absolutePath), ".", walkFn); err != nil {
		return nil, nil, err
	}

	g.Wait()

	return removedPaths, failedPaths, nil
}
