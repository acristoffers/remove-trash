// Package remove_trash exports the Traverse function, which traverses a path
// and removes all trash files and folders in it, reporting progress and
// calculating the size freed by the operation.
package remove_trash

import (
	"os"
	"path/filepath"
	"strings"
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

// Instead of throwing an error and stopping, the errors are collected and
// returned at the end. This represents files/folders which could not be deleted
// by os.RemoveAll
type FailedPath struct {
	Path string
	Err  error
}

// Traverses path, returning a list of files/folders that were removed.
// If dryRun is true, do not remove any file.
// pr is called to report progress.
func Traverse(path string, dryRun bool, pr chan<- ProgressReport) ([]string, []FailedPath, error) {
	defer close(pr)

	var removedPaths []string = make([]string, 0, 1000)
	var failedPaths []FailedPath = make([]FailedPath, 0, 1000)

	absolutePath, err := absolutePathWithHomeReplaced(path)
	if err != nil {
		return nil, nil, err
	}

	filter := regexFilter{}
	if err := filter.compileRegexes(); err != nil {
		return nil, nil, err
	}

	stat, err := os.Lstat(absolutePath)
	if err != nil {
		return nil, nil, err
	}

	if filter.isTrash(stat.Name()) {
		totalSize := uint64(stat.Size())

		if stat.IsDir() {
			totalSize = nodeSize(absolutePath)
		}

		if err := os.RemoveAll(absolutePath); err != nil {
			failedPaths = append(failedPaths, FailedPath{absolutePath, err})
		} else {
			removedPaths = append(removedPaths, absolutePath)
			pr <- ProgressReport{1, 1, totalSize}
		}

		return removedPaths, failedPaths, nil
	} else if filter.shouldIgnore(stat.Name()) {
		return removedPaths, failedPaths, nil
	}

	total := uint64(0)
	count := uint64(0)

	if stat.IsDir() {
		remove := make(chan string, 100)
		failed := make(chan FailedPath, 100)
		var counter atomic.Int64

		go walkFiltered(absolutePath, filter, remove, failed, &counter)

		for {
			select {
			case r, ok := <-remove:
				if ok {
					total += 1
					totalSize := nodeSize(r)

					pr <- ProgressReport{count, total, 0}

					if dryRun {
						count += 1
						removedPaths = append(removedPaths, r)
						pr <- ProgressReport{count, total, totalSize}
					} else if err := os.RemoveAll(r); err != nil {
						failedPaths = append(failedPaths, FailedPath{r, err})
					} else {
						count += 1
						removedPaths = append(removedPaths, r)
						pr <- ProgressReport{count, total, totalSize}
					}
				} else {
					remove = nil
				}
			case f, ok := <-failed:
				if ok {
					failedPaths = append(failedPaths, f)
				} else {
					failed = nil
				}
			}

			if remove == nil && failed == nil {
				break
			}
		}
	}

	return removedPaths, failedPaths, nil
}

func absolutePathWithHomeReplaced(path string) (string, error) {
	var absolutePath string

	homePath, err := os.UserHomeDir()
	if err != nil {
		return absolutePath, err
	}

	if strings.HasPrefix(path, "~/") {
		path = filepath.Join(homePath, path[2:])
	}

	absolutePath, err = filepath.Abs(path)
	if err != nil {
		return absolutePath, err
	}

	return absolutePath, nil
}

func nodeSize(path string) uint64 {
	totalSize := uint64(0)
	readSize := func(path string, file os.FileInfo, err error) error {
		if file.Mode().IsRegular() {
			totalSize += uint64(file.Size())
		}
		return nil
	}
	filepath.Walk(path, readSize)
	return totalSize
}
