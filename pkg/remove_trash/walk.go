package remove_trash

import (
	"io/fs"
	"os"
	"path/filepath"
	"sync/atomic"
	"syscall"
)

type walkerFilter interface {
	shouldDelete(name string) bool
	shouldIgnore(name string) bool
}

func walkFiltered(path string, filter walkerFilter, remove chan<- string, failed chan<- FailedPath, counter *atomic.Int64) {
	var ds []fs.DirEntry
	var err error

	for {
		ds, err = os.ReadDir(path)
		if err != nil {
			if pathErr, ok := err.(*os.PathError); ok {
				// If the error is due to too many open files, try again. Forever.
				if pathErr.Err == syscall.EMFILE {
					continue
				}
			}
			failed <- FailedPath{path, err}
		}
		break
	}

	for _, d := range ds {
		basename := d.Name()

		if filter.shouldIgnore(basename) {
		} else if filter.shouldDelete(basename) {
			remove <- filepath.Join(path, basename)
		} else if d.IsDir() {
			counter.Add(1)
			go walkFiltered(filepath.Join(path, basename), filter, remove, failed, counter)
		}
	}

	if counter.Add(-1) == -1 {
		close(remove)
		close(failed)
	}
}
