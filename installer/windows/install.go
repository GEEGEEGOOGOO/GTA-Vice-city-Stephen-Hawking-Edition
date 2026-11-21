package main

import (
	"archive/zip"
	"bytes"
	"compress/bzip2"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

//go:embed resources
var resources embed.FS

const edition = "GTA Stephen Hawking Edition"
const payload = "hawking-vice-city-macos-arm64.zip"

type gameFile struct {
	Path, Kind, SHA256, Base, Member string
	BaseHash                         string `json:"base_sha256"`
	Size                             int64
	Operations                       []operation
}
type operation struct {
	Source         string
	Offset, Length int64
}

func (op *operation) UnmarshalJSON(raw []byte) error {
	var fields []json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	if len(fields) != 3 {
		return errors.New("invalid archive operation")
	}
	for i, target := range []any{&op.Source, &op.Offset, &op.Length} {
		if err := json.Unmarshal(fields[i], target); err != nil {
			return err
		}
	}
	return nil
}

type packageInfo struct {
	URL, SHA256, InnerPath string
	Size                   int64
}
type manifest struct {
	Version int
	Files   []gameFile
}

func readJSON(name string, out any) error {
	raw, err := resources.ReadFile("resources/" + name)
	if err != nil {
		return err
	}
	return json.Unmarshal(raw, out)
}

func checksum(r io.Reader) (string, error) {
	h := sha256.New()
	if _, err := io.Copy(h, r); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
func hashFile(name string) (string, error) {
	f, err := os.Open(name)
	if err != nil {
		return "", err
	}
	defer f.Close()
	return checksum(f)
}

func gameRoot(selection string) (string, error) {
	if filepath.Ext(selection) == ".app" {
		selection = filepath.Join(selection, "Contents", "Resources", "GameData")
	}
	for _, candidate := range []string{selection, filepath.Join(selection, "GameData")} {
		if st, err := os.Stat(filepath.Join(candidate, "data")); err == nil && st.IsDir() {
			if st, err = os.Stat(filepath.Join(candidate, "models")); err == nil && st.IsDir() {
				return candidate, nil
			}
		}
	}
	return "", errors.New("Choose the original Vice City folder containing the data and models folders.")
}

func findBase(root string, records []gameFile) (map[string]string, error) {
	index := map[string]string{}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if p == root {
			return nil
		}
		if strings.HasPrefix(d.Name(), ".") || strings.HasSuffix(strings.ToLower(d.Name()), ".bak") {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.Type().IsRegular() {
			rel, err := filepath.Rel(root, p)
			if err != nil {
				return err
			}
			key := strings.ToLower(filepath.ToSlash(rel))
			if _, exists := index[key]; exists {
				return fmt.Errorf("conflicting filenames in the base game: %s", rel)
			}
			index[key] = p
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	bases := map[string]string{}
	var missing []string
	seen := map[string]bool{}
	for _, r := range records {
		if r.Base == "" || seen[r.Base] {
			continue
		}
		seen[r.Base] = true
		if file := index[strings.ToLower(r.Base)]; file != "" {
			for _, candidate := range []string{file, file + ".bak"} {
				if digest, err := hashFile(candidate); err == nil && digest == r.BaseHash {
					bases[r.Base] = candidate
					break
				}
			}
		}
		if bases[r.Base] == "" {
			name := "resources/base/" + strings.ToLower(r.Base)
			if f, err := resources.Open(name); err == nil {
				digest, digestErr := checksum(f)
				f.Close()
				if digestErr == nil && digest == r.BaseHash {
					bases[r.Base] = name
				}
			}
		}
		if bases[r.Base] == "" {
			missing = append(missing, r.Base)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("%d files are missing or differ from the supported classic PC data. First mismatch: %s.", len(missing), missing[0])
	}
	return bases, nil
}

func gameInput(name string) (io.ReadSeekCloser, error) {
	if strings.HasPrefix(name, "resources/base/") {
		raw, err := resources.ReadFile(name)
		return readSeekCloser{bytes.NewReader(raw)}, err
	}
	return os.Open(name)
}

type readSeekCloser struct{ *bytes.Reader }

func (readSeekCloser) Close() error { return nil }

func newFile(root, entry string) (*os.File, error) {
	if path.Clean(entry) != entry || !fs.ValidPath(entry) || strings.ContainsAny(entry, "\\:") {
		return nil, fmt.Errorf("invalid path %q", entry)
	}
	destination := filepath.Join(root, filepath.FromSlash(entry))
	if err := os.MkdirAll(filepath.Dir(destination), 0755); err != nil {
		return nil, err
	}
	return os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644)
}

func extractFromZIP(z *zip.Reader, name, dest string) error {
	src, err := z.Open(name)
	if err != nil {
		return err
	}
	defer src.Close()
	return writeFile(dest, func(w io.Writer) error { _, err := io.Copy(w, src); return err })
}

func writeFile(name string, write func(io.Writer) error) error {
	out, err := os.Create(name)
	if err != nil {
		return err
	}
	err = write(out)
	closeErr := out.Close()
	if err != nil {
		return err
	}
	return closeErr
}

func assembleArchive(out io.Writer, source, literal io.ReadSeeker, ops []operation, size int64) error {
	remaining := size
	for _, op := range ops {
		var input io.ReadSeeker
		switch op.Source {
		case "copy":
			input = source
		case "literal":
			input = literal
		default:
			return errors.New("unknown archive source")
		}
		if op.Offset < 0 || op.Length <= 0 || op.Length > remaining {
			return errors.New("invalid archive offset or length")
		}
		if _, err := input.Seek(op.Offset, io.SeekStart); err != nil {
			return err
		}
		if _, err := io.CopyN(out, input, op.Length); err != nil {
			return err
		}
		remaining -= op.Length
	}
	if remaining != 0 {
		return errors.New("incomplete archive patch")
	}
	return nil
}

func installInto(packageZIP, gameDir, temp string, records []gameFile, bases map[string]string) error {
	z, err := zip.OpenReader(packageZIP)
	if err != nil {
		return err
	}
	defer z.Close()
	for _, r := range records {
		if err := installEntry(&z.Reader, gameDir, temp, r, bases); err != nil {
			return fmt.Errorf("%s: %w", r.Path, err)
		}
	}
	return fs.WalkDir(resources, "resources/runtime", func(name string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		out, err := newFile(gameDir, strings.TrimPrefix(name, "resources/runtime/"))
		if err != nil {
			return err
		}
		defer out.Close()
		input, err := resources.Open(name)
		if err != nil {
			return err
		}
		defer input.Close()
		_, err = io.Copy(out, input)
		return err
	})
}

func installEntry(z *zip.Reader, gameDir, temp string, r gameFile, bases map[string]string) error {
	out, err := newFile(gameDir, r.Path)
	if err != nil {
		return err
	}
	defer out.Close()
	hash := sha256.New()
	w := io.MultiWriter(out, hash)
	if err = applyEntry(w, z, temp, r, bases[r.Base]); err != nil {
		return err
	}
	st, err := out.Stat()
	if err != nil {
		return err
	}
	if st.Size() != r.Size || hex.EncodeToString(hash.Sum(nil)) != r.SHA256 {
		return errors.New("file did not match its checksum")
	}
	return out.Close()
}

func applyEntry(out io.Writer, z *zip.Reader, temp string, r gameFile, base string) error {
	if r.Kind == "new" {
		src, err := z.Open(r.Member)
		if err != nil {
			return err
		}
		defer src.Close()
		_, err = io.Copy(out, src)
		return err
	}
	src, err := gameInput(base)
	if err != nil {
		return err
	}
	defer src.Close()
	switch r.Kind {
	case "base":
		_, err = io.Copy(out, src)
		return err
	case "diff":
		patch, err := z.Open(r.Member)
		if err != nil {
			return err
		}
		defer patch.Close()
		raw, err := io.ReadAll(patch)
		if err != nil {
			return err
		}
		return patchBSDiff(out, src, raw, r.Size)
	case "archive":
		literal := filepath.Join(temp, "literal")
		if err := extractFromZIP(z, r.Member, literal); err != nil {
			return err
		}
		defer os.Remove(literal)
		changes, err := os.Open(literal)
		if err != nil {
			return err
		}
		defer changes.Close()
		return assembleArchive(out, src, changes, r.Operations, r.Size)
	default:
		return fmt.Errorf("unsupported operation %s", r.Kind)
	}
}

func install(selection, destination, localZIP string, progress func(string)) error {
	root, err := gameRoot(selection)
	if err != nil {
		return err
	}
	if _, err = os.Lstat(destination); !os.IsNotExist(err) {
		if err != nil {
			return err
		}
		return errors.New("The mod is already installed at the selected location. Choose a new folder for another copy.")
	}
	var m manifest
	var info packageInfo
	if err = readJSON("manifest.json", &m); err != nil {
		return err
	}
	if err = readJSON("package.json", &info); err != nil {
		return err
	}
	if m.Version != 1 {
		return errors.New("unsupported game package version")
	}
	progress("Checking the original Vice City files…")
	bases, err := findBase(root, m.Files)
	if err != nil {
		return err
	}
	parent := filepath.Dir(destination)
	if err = os.MkdirAll(parent, 0755); err != nil {
		return err
	}
	temp, err := os.MkdirTemp(parent, ".hawking-install-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temp)
	if localZIP == "" {
		progress(fmt.Sprintf("Downloading the mod files (%.0f MiB)…", float64(info.Size)/(1024*1024)))
		localZIP = filepath.Join(temp, "player.zip")
		if err = download(info, localZIP); err != nil {
			return err
		}
	}
	progress("Verifying the mod download…")
	if digest, err := hashFile(localZIP); err != nil || digest != info.SHA256 {
		return errors.New("the mod download did not match its checksum")
	}
	packageZIP := filepath.Join(temp, payload)
	z, err := zip.OpenReader(localZIP)
	if err != nil {
		return err
	}
	err = extractFromZIP(&z.Reader, info.InnerPath, packageZIP)
	z.Close()
	if err != nil {
		return err
	}
	if localZIP == filepath.Join(temp, "player.zip") {
		if err = os.Remove(localZIP); err != nil {
			return err
		}
	}
	progress("Assembling and verifying the game files…")
	gameDir := filepath.Join(temp, "game")
	if err = installInto(packageZIP, gameDir, temp, m.Files, bases); err != nil {
		return err
	}
	if _, err = os.Lstat(destination); !os.IsNotExist(err) {
		return errors.New("the install location already exists")
	}
	return os.Rename(gameDir, destination)
}

func download(info packageInfo, dest string) error {
	client := http.Client{Timeout: 45 * time.Minute}
	response, err := client.Get(info.URL)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("GitHub returned %s for the download", response.Status)
	}
	return writeFile(dest, func(out io.Writer) error {
		n, err := io.Copy(out, io.LimitReader(response.Body, info.Size+1))
		if err != nil {
			return err
		}
		if n != info.Size {
			return errors.New("the download ended at an unexpected size")
		}
		return nil
	})
}

func readOffset(b []byte) int64 {
	n := int64(b[7] & 0x7f)
	for i := 6; i >= 0; i-- {
		n = n*256 + int64(b[i])
	}
	if b[7]&0x80 != 0 {
		return -n
	}
	return n
}
func patchBSDiff(dest io.Writer, source io.Reader, patch []byte, expected int64) error {
	if len(patch) < 32 || string(patch[:8]) != "BSDIFF40" {
		return errors.New("invalid BSDIFF patch")
	}
	a, b, size := readOffset(patch[8:16]), readOffset(patch[16:24]), readOffset(patch[24:32])
	n := int64(len(patch))
	if a < 0 || b < 0 || a > n-32 || b > n-32-a || size != expected {
		return errors.New("invalid BSDIFF block lengths")
	}
	control := bzip2.NewReader(bytes.NewReader(patch[32 : 32+a]))
	delta := bzip2.NewReader(bytes.NewReader(patch[32+a : 32+a+b]))
	extra := bzip2.NewReader(bytes.NewReader(patch[32+a+b:]))
	original, err := io.ReadAll(source)
	if err != nil {
		return err
	}
	var oldPos, newPos int64
	var block [24]byte
	buf := make([]byte, 64*1024)
	for newPos < size {
		if _, err := io.ReadFull(control, block[:]); err != nil {
			return err
		}
		more, insert, skip := readOffset(block[:8]), readOffset(block[8:16]), readOffset(block[16:])
		if more < 0 || insert < 0 || more > size-newPos || insert > size-newPos-more {
			return errors.New("invalid BSDIFF control record")
		}
		for left := more; left > 0; {
			amount := min(int64(len(buf)), left)
			chunk := buf[:amount]
			if _, err := io.ReadFull(delta, chunk); err != nil {
				return err
			}
			for i := range chunk {
				index := oldPos + int64(i)
				if index >= 0 && index < int64(len(original)) {
					chunk[i] += original[index]
				}
			}
			if _, err := dest.Write(chunk); err != nil {
				return err
			}
			oldPos += amount
			left -= amount
		}
		if _, err := io.CopyN(dest, extra, insert); err != nil {
			return err
		}
		newPos += more + insert
		oldPos += skip
	}
	return nil
}
