package cmd

import (
	"fmt"
	"os"
	"sync"
	"sync/atomic"

	"github.com/acristoffers/remove-trash/pkg/remove_trash"
	"github.com/inhies/go-bytesize"
	"github.com/schollz/progressbar/v3"
	"github.com/spf13/cobra"
)

var RootCmd = &cobra.Command{
	Use:   "remove-trash [PATH]",
	Short: "Removes trash files from the filesystem starting at PATH",
	Long: `Removes files like .DS_Store and Thumb.db from the disk, as well as other "useless" files:

	- .DS_Store
	- .cache
	- .gradle
	- .mypy_cache
	- .sass-cache
	- .textpadtmp
	- Thumbs.db
	- __pycache__
	- _build
	- build
	- slprj
	- zig-cache
	- zig-out
	- *.slxc
	- *.bak
	- ~*`,
	Run: func(cmd *cobra.Command, args []string) {
		version, err := cmd.Flags().GetBool("version")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Could not parse options: %s\n", err)
			os.Exit(1)
		}

		dryRun, err := cmd.Flags().GetBool("dry-run")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Could not parse options: %s\n", err)
			os.Exit(1)
		}

		noErrors, err := cmd.Flags().GetBool("no-error")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Could not parse options: %s\n", err)
			os.Exit(1)
		}

		if version {
			fmt.Printf("Version %s", remove_trash.Version)
			return
		} else if len(args) == 0 {
			cmd.Help()
			return
		}

		var removedTotal []string
		var failedTotal []remove_trash.FailedPath

		var countAtomic atomic.Uint64
		var sizeAtomic atomic.Uint64
		var totalAtomic atomic.Uint64

		var bar *progressbar.ProgressBar = progressbar.NewOptions(1,
			progressbar.OptionSetWriter(os.Stdout),
			progressbar.OptionSetDescription("Removed"),
			progressbar.OptionThrottle(0),
			progressbar.OptionShowCount(),
			progressbar.OptionFullWidth(),
			progressbar.OptionSetRenderBlankState(true))

		var wg sync.WaitGroup
		var mutex sync.Mutex
		var channels []<-chan remove_trash.ProgressReport

		for _, pathPtr := range args {
			var path string = pathPtr
			channel := make(chan remove_trash.ProgressReport, 10)
			channels = append(channels, channel)

			worker := func() {
				defer wg.Done()

				removed, failed, err := remove_trash.Traverse(path, dryRun, channel)
				if err != nil {
					bar.Clear()
					fmt.Printf("An error occurred: %s\n", err)
				}

				mutex.Lock()
				defer mutex.Unlock()

				failedTotal = append(failed, failed...)
				removedTotal = append(removedTotal, removed...)
			}

			wg.Add(1)
			go worker()
		}

		for pr := range merge(channels...) {
			sizeAtomic.Add(pr.Bytes)

			// We actually only count from 1 in 1, so we can keep track of all
			// goroutines like this
			if pr.Bytes != 0 {
				countAtomic.Add(1)
			} else {
				totalAtomic.Add(1)
			}

			total := totalAtomic.Load()
			count := countAtomic.Load()

			// The progressbar will finish and disappear if total == count :/
			if total == count {
				count -= 1
			}

			bar.ChangeMax64(int64(total))
			bar.Describe(fmt.Sprintf("Removed %s", bytesize.New(float64(sizeAtomic.Load()))))
			bar.Set64(int64(count))
		}

		wg.Wait()

		bar.ChangeMax64(int64(totalAtomic.Load()))
		bar.Set64(int64(countAtomic.Load()))

		if dryRun {
			bar.Clear()
			for _, path := range removedTotal {
				fmt.Printf("Removed %s\n", path)
			}
			fmt.Printf("Would remove %d files for a total of %s\n", len(removedTotal), bytesize.New(float64(sizeAtomic.Load())))
		} else if !noErrors {
			for _, failed := range failedTotal {
				fmt.Fprintln(os.Stderr, failed.Err)
			}
		}
	},
}

func Execute() {
	err := RootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	RootCmd.Flags().BoolP("version", "v", false, "Prints the version.")
	RootCmd.Flags().BoolP("dry-run", "d", false, "Shows what would be done, but does not do anything.")
	RootCmd.Flags().BoolP("no-error", "n", false, "Do not print file delete errors at the end.")
}

func merge(cs ...<-chan remove_trash.ProgressReport) <-chan remove_trash.ProgressReport {
	zip := make(chan remove_trash.ProgressReport, 100)

	var wg sync.WaitGroup
	wg.Add(len(cs))

	for _, c := range cs {
		go func(c <-chan remove_trash.ProgressReport) {
			for v := range c {
				zip <- v
			}
			wg.Done()
		}(c)
	}

	go func() {
		wg.Wait()
		close(zip)
	}()

	return zip
}
