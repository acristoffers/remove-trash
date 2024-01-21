package cmd

import (
	"fmt"
	"os"
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
         
  * .DS_Store
  * Thumb.db`,
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

		if version {
			fmt.Printf("Version %s", remove_trash.Version)
			return
		}

		if !version && !dryRun && len(args) == 0 {
			cmd.Help()
		}

		removedTotal := []string{}
		failedTotal := []remove_trash.FailedPath{}

		var countAtomic atomic.Uint64
		var sizeAtomic atomic.Uint64
		var totalAtomic atomic.Uint64

		bar := progressbar.NewOptions(1,
			progressbar.OptionSetWriter(os.Stdout),
			progressbar.OptionSetDescription("Removed"),
			progressbar.OptionThrottle(0),
			progressbar.OptionShowCount(),
			progressbar.OptionFullWidth(),
			progressbar.OptionSetRenderBlankState(true))
		report := func(count uint64, total uint64, size uint64) {
			countAtomic.Store(count)
			sizeAtomic.Add(size)
			totalAtomic.Store(total)

			// The progressbar will finish and disappear if total == count :/
			if total == count {
				count -= 1
			}

			bar.ChangeMax64(int64(total))
			bar.Describe(fmt.Sprintf("Removed %s", bytesize.New(float64(sizeAtomic.Load()))))
			bar.Set64(int64(count))
		}

		for _, path := range args {
			removed, failed, err := remove_trash.Traverse(path, dryRun, report)
			if err != nil {
				bar.Clear()
				fmt.Printf("An error occurred: %s\n", err)
			}

			failedTotal = append(failed, failed...)
			removedTotal = append(removedTotal, removed...)
		}

		bar.ChangeMax64(int64(totalAtomic.Load()))
		bar.Set64(int64(countAtomic.Load()))

		if dryRun {
			bar.Clear()
			for _, path := range removedTotal {
				fmt.Printf("Removed %s\n", path)
			}
			fmt.Printf("Would remove %d files for a total of %s\n", len(removedTotal), bytesize.New(float64(sizeAtomic.Load())))
		} else {
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
}
