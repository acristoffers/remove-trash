/*
 * Removes files like .DS_Store and Thumb.db from the disk, as well as other
 * "useless" files:
 *
 *   * .DS_Store
 *   * Thumb.db
 *
 * Usage:
 *   remove-trash [PATH] [flags]
 *
 * Flags:
 *   -d, --dry-run   Shows what would be done, but does not do anything.
 *   -h, --help      help for remove-trash
 *   -v, --version   Prints the version.
 */
package main

import "github.com/acristoffers/remove-trash/cmd"

func main() {
	cmd.Execute()
}
