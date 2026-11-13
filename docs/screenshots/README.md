# Real CleanJunk Screenshots

This folder is reserved for **verified screenshots captured from an actual running macOS CleanJunk application**, never AI-generated imitations.

## Current status

The repository includes [design concepts](../previews/) labeled **not actual app screenshots**. We have not yet captured verified real UI screenshots from a macOS 26 desktop. Do not remove the concept labels until genuine screenshots are added.

## Capture steps

1. Build and open **CleanJunk.app** on macOS 26. No Apple Developer membership is necessary for local ad-hoc developer builds.
2. Prefer a **disposable test account** with fake project filenames and package metadata. A real user's home folder, installed software and project paths can reveal sensitive information.
3. From the repository root, run:

~~~bash
bash scripts/capture-screenshots.sh
~~~

4. Visit **Overview**, **Space Explorer**, **Packages**, and **System Data** as prompted.
5. For each page, click the actual CleanJunk window when macOS window selection appears.
6. Verify the following files exist and contain genuine UI captures:

~~~text
docs/screenshots/overview.png
docs/screenshots/space-explorer.png
docs/screenshots/packages.png
docs/screenshots/system-data.png
~~~

7. Check every screenshot for usernames, file paths, project names, Homebrew package lists, customer data, notifications and other secrets. Crop or redact any private content before publishing.
8. Only after reviewing the files, commit them:

~~~bash
git add docs/screenshots/*.png
git commit -m "docs: add verified macOS interface screenshots"
git push
~~~

The script never uploads or commits anything automatically and never starts GitHub Actions. If macOS denies capture, grant screen capture access in **System Settings → Privacy & Security → Screen & System Audio Recording**, then restart the terminal if necessary.

## Promote real screenshots to the root README

Once the above PNGs have been verified, replace the **design concept** image references in README.md with the corresponding **docs/screenshots/*.png** references. Update the caption to say when and on which macOS version the shots were taken.

**Do not present a mockup, SVG illustration, AI-generated picture or simulated dashboard as a real screenshot.**
