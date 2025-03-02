#!/usr/bin/env bash
#Automated ZFS compressiontest

BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch
git update-index -q --refresh
CHANGED=$(git diff --name-only origin/$BRANCH)
if [ ! -z "$CHANGED" ]; then
    echo "script requires update"
    git reset --hard
    git checkout $BRANCH
    git pull
    echo "script updated"
    exit 1
else
    echo "script up-to-date"
fi

now=$(date +%s)

MODE="NONE"
IO="sequential random"
RW="writes reads readwrite"
INSTALL="FALSE"
RESET="FALSE"
GZIP="gzip gzip-1 gzip-2 gzip-3 gzip-4 gzip-5 gzip-6 gzip-7 gzip-8 gzip-9"
ZSTD="zstd zstd-1 zstd-2 zstd-3 zstd-4 zstd-5 zstd-6 zstd-7 zstd-8 zstd-9 zstd-10 zstd-11 zstd-12 zstd-13 zstd-14 zstd-15 zstd-16 zstd-17 zstd-18 zstd-19"
ZSTDFAST="zstd-fast zstd-fast-1 zstd-fast-2 zstd-fast-3 zstd-fast-4 zstd-fast-5 zstd-fast-6 zstd-fast-7 zstd-fast-8 zstd-fast-9 zstd-fast-10 zstd-fast-20 zstd-fast-30 zstd-fast-40 zstd-fast-50 zstd-fast-60 zstd-fast-70 zstd-fast-80 zstd-fast-90 zstd-fast-100 zstd-fast-500 zstd-fast-1000"
TYPE="WIKIPEDIA"
TESTRESULTS="test_results_$now.txt"
TESTRESULTSTERSE="test_results_$now.terse"
OS="$(uname -s)"
ZFS_CMD=./zfs/cmd/zfs/zfs
ZPOOL_CMD=./zfs/cmd/zpool/zpool
TESTPOOL_MANAGE="TRUE"
TESTPOOL_VDEVS="RAMDISK"
TESTPOOL_NAME="testpool"
TESTDATASET="$TESTPOOL_NAME/fs1"

#Export fio settings
export SYNC_TYPE=0
export DIRECT=1
export NUMJOBS=16
export DIRECTORY="/$TESTDATASET/"
export RUNTIME=3
export BLOCKSIZE="128k"
export FILESIZE="100m"
export FILE_SIZE="100m"
export RANDSEED=1234
export PERF_RANDSEED=1234
export COMPPERCENT=50
export PERF_COMPPERCENT=50
export COMPCHUNK=0
export PERF_COMPCHUNK=0

#ZFS Fio Customisations
MODIFIER="--unified_rw_reporting=1"

if [ $# -eq 0 ]; then
    echo "Missing options!"
    echo "(run $0 -h for help)"
    echo ""
    exit 0
fi

sha256sum () {
    if [ "$OS" = "FreeBSD" ]; then
        if [ "$1" = "--check" ]; then
            LINE="$(cat -)"
            CSUM="${LINE#* = }"
            F1="${LINE#*(}"
            FILE="${F1%)*}"
            sha256 -c "$CSUM" $FILE
        else
            sha256 "$@"
        fi
    else
        /bin/sha256sum "$@"
    fi
}

while getopts "p:t:ribfhc:s:SP:F:" OPTION; do
    case $OPTION in
        p)
            TESTRESULTS="$OPTARG-$TESTRESULTS.txt"
            TESTRESULTSTERSE="$OPTARG-$TESTRESULTS.terse"
            echo "Results file of the test is called: ./$TESTRESULTS"
            ;;
        t)
            TYPE="$OPTARG"
            case $TYPE in
                [wW])
                    echo "Selected highly compressible Wikipedia file"
                    TYPE="WIKIPEDIA"
                    ;;
                [mM])
                    echo "Selected nearly uncompressible MPEG4 file"
                    TYPE="MPEG4"
                    ;;
                *)
                    echo "Unknown Selection of Testtype. Using default"
                    TYPE="WIKIPEDIA"
                    ;;
            esac
            ;;
        r)
            RESET="TRUE"
            echo "Selected RESET of ZSTD test-installation"
            ;;
        i)
            INSTALL="TRUE"
            echo "Selected INSTALL of ZSTD test-installation"
            ;;
        b)
            MODE="BASIC"
            IO="sequential"
            ALGO="off lz4 zle lzjb gzip zstd"
            echo "Selected BASIC compression test"
            ;;
        f)
            MODE="FULL"
            ALGO="off lz4 zle lzjb $GZIP $ZSTD $ZSTDFAST"
            echo "Selected FULL compression test"
            echo "This might take a while..."
            ;;
        c)
            MODE="CUSTOM"
            ALGO="$OPTARG"
            echo "Selected custom compression test using the following algorithms:"
            echo "$ALGO"
            ;;
        s)
            TESTPOOL_VDEVS="$OPTARG"
            echo "Doing custom ZFS Storage test. This will do: zpool create $TESTPOOL_NAME $TESTPOOL_VDEVS"
            echo "This will destroy all data on these drives!"
            read -p "Are you sure you want to continue? (y/N)" -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "OK. Continuing..."
            else
                echo "exiting..."
                exit 1
            fi
            ;;
        S)
            echo "Using system-wide ZFS installation"
            ZFS_CMD=`sudo which zfs`
            ZPOOL_CMD=`sudo which zpool`
            if [ -z "$ZFS_CMD" -o -z "$ZPOOL_CMD" ]; then
                echo "No system-wide ZFS installation found, please install"
                exit 1
            fi
            ;;
        P)
            TESTPOOL_NAME=$OPTARG
            TESTPOOL_MANAGE="FALSE"
            TESTDATASET="$TESTPOOL_NAME/fs1"
            export DIRECTORY="/$TESTDATASET/"
            echo "Using existing ZFS pool: '$TESTPOOL_NAME'"
            ;;
        F)
            FILE_SIZE=$OPTARG
            FILESIZE=$OPTARG
            ;;
        h)
            echo "Usage: $0 [OPTION]... <-h|-b|-f|-c <\"COMPRESS[ COMPRESS[ ...]]\">>"
            echo ""
            echo "  Mandatory operation-mode options (mutually exclusive):"
            echo "   -h                help (this output)"
            echo "   -b                execute a basic compression test containing: off lz4 zle lzjb gzip zstd"
            echo "   -f                execute a full compression test containing all currently available ZFS compression algorithms"
            echo "   -c <\"comp_list\">  execute on space-separated list of compression types. Supported compression types:"
            echo "        off lz4 zle lzjb $GZIP"
            echo "        $ZSTD"
            echo "        $ZSTDFAST"
            echo ""
            echo "  Other options:"
            echo "   -i                install a ZFS test environment"
            echo "   -r                reset a ZFS test environment"
            echo "   -S                use system ZFS environment"
            echo "   -p <prefix>       prefix to the test_result files"
            echo "   -t <w|m>          select the type of test:"
            echo "                       w for highly compressible wikipedia file"
            echo "                       m for nearly uncompressible mpeg4 file"
            echo "   -s \"<vdev_setup>\" to use custom devices and raid setups. (DANGEROUS!)"
            echo "      example for custom storagepools: $0 -s \"raidz1 /dev/sga /dev/sgb /dev/sgc\""
            echo "   -P <pool_name>    use existing ZFS Pool for the tests"
            echo "   -F <file_size>    size of files used in the 'fio' tests (if you benchmark on"
            echo "                     real block devices, this should be larger than your RAM)"
            exit 0
            ;;
        *)
            echo "Unknown option -$OPTION"
            exit 1
            ;;
    esac
done

echo "creating output folder"
mkdir ./TMP

echo "checking if you git cloned zfs"
[ ! -e ./zfs/.git ] && { echo "You need to clone zfs first! # git clone https://github.com/zfsonlinux/zfs"; exit 1; }

if [ $INSTALL = "TRUE" ]; then
    cd ./zfs
    echo "unloading and unlinking possible previous build"
    sudo ./scripts/zfs.sh -u
    sudo ./scripts/zfs-helpers.sh -r
    make -s distclean >> /dev/null

    echo "rebuilding zfs"
    sh autogen.sh >> /dev/null
    ./configure --enable-debug >> /dev/null
    make -s -j$(nproc) >> /dev/null

    echo "loading zfs"
    sudo ./scripts/zfs-helpers.sh -i
    sudo ./scripts/zfs.sh
    cd ..
fi

if [ ! -e "$ZPOOL_CMD" ] ; then
    echo "missing command for 'zpool': $ZPOOL_CMD"
    exit 1
fi

if [ ! -e "$ZFS_CMD" ] ; then
    echo "missing command for 'zfs': $ZFS_CMD"
    exit 1
fi

if [  $MODE = "FULL" -o $MODE = "BASIC" -o $MODE = "CUSTOM" ]; then
    if [ $TESTPOOL_MANAGE = "TRUE" ] ; then
        echo "destroy testpool and clean ram of previous broken/canceled tests"
        sudo $ZPOOL_CMD destroy $TESTPOOL_NAME >> /dev/null
        if [ $TESTPOOL_VDEVS = "RAMDISK" ]; then
            if [ "$OS" = "FreeBSD" ]; then
                MDDEV="$(mdconfig -a -t swap -s 2000m)"
                TESTPOOL_VDEVS="/dev/${MDDEV}"
            else
                TESTPOOL_VDEVS="/dev/shm/pooldisk.img"
                echo "removing /dev/shm/pooldisk.img (RAMDISK)"
                sudo rm -f $TESTPOOL_VDEVS

                echo "creating virtual pool drive"
                truncate -s 2000m $TESTPOOL_VDEVS
            fi
        fi

        echo "creating zpool $TESTPOOL_NAME on $TESTPOOL_VDEVS"
        sudo $ZPOOL_CMD create -f -o ashift=12 $TESTPOOL_NAME $TESTPOOL_VDEVS
    fi

    # Downloading and may be uncompressing file
    FILENAME=""
    case "$TYPE" in
        WIKIPEDIA)
            echo "downloading and extracting enwik9 testset"
            sudo wget -nc http://mattmahoney.net/dc/enwik9.zip
            sudo unzip -n enwik9.zip
            FILENAME="enwik9"
            ;;
        MPEG4)
            echo "downloading a MPEG4 testfile"
            sudo wget -nc http://distribution.bbb3d.renderfarming.net/video/mp4/bbb_sunflower_native_60fps_stereo_abl.mp4
            FILENAME="bbb_sunflower_native_60fps_stereo_abl.mp4"
            ;;
        *)
            echo "ERROR: $TYPE is not unknown"
            exit 1
            ;;
    esac
    chksum=$(sha256sum $FILENAME)
    echo "" >> "./$TESTRESULTS"
    echo "Test with $FILENAME file" >> "./$TESTRESULTS"
    if [ "$OS" = "FreeBSD" ]; then
        echo "$(sysctl -n hw.ncpu) x $(sysctl -n hw.model)" >> "./$TESTRESULTS"
    else
        grep "^model name" /proc/cpuinfo |sort -u >> "./$TESTRESULTS"
        grep "^flags" /proc/cpuinfo |sort -u >>  "./$TESTRESULTS"
    fi
    echo "ZFS Storagepool-Device(s): $TESTPOOL_VDEVS" >> "./$TESTRESULTS"
    echo "" >> "./$TESTRESULTS"
    echo "starting compression test suite"
    echo "" >> "./$TESTRESULTS"

    for io in $IO; do
        echo "Starting $io compression-performance tests"
        sudo $ZFS_CMD create $TESTDATASET
        if [ $io = "random" ]; then
            sudo $ZFS_CMD set recordsize=8K  $TESTDATASET
        else
            sudo $ZFS_CMD set recordsize=1M  $TESTDATASET
        fi
        for comp in $ALGO; do
            echo ""
            echo "running benchmarks for $comp"
            sudo $ZFS_CMD set compression=$comp $TESTDATASET
            if [ $? -ne 0 ]; then
                echo "Could not set compression to $comp! Skipping test."
            else
                echo "Running compression ratio test"
                echo “$io Benchmark Results for $comp” >> "./$TESTRESULTS"
                dd if=./$FILENAME of=/$TESTDATASET/$FILENAME bs=4M 2>&1 |grep -v records >> "./$TESTRESULTS"
                sync
                echo "Compression Ratio:" >> "./$TESTRESULTS"
                compressionratio=$($ZFS_CMD get -H -o value compressratio $TESTDATASET)
                echo "$compressionratio" >> "./$TESTRESULTS"
                compressionratio=${compressionratio%?}
                echo ""  >> "./$TESTRESULTS"
                echo "verifying testhash"
                cd /$TESTDATASET/
                chkresult=$(echo "$chksum" | sha256sum --check)
                cd - >> /dev/null
                echo "hashcheck result: $chkresult" >> "./$TESTRESULTS"
                echo "" >> "./$TESTRESULTS"
                rm /$TESTDATASET/$FILENAME
                echo "" >> "./$TESTRESULTS"
                for rw in $RW; do
                    echo "Running $rw bandwidth test"
                    bandwidth=0
                    echo "$rw (de)compression results for $comp" >> "./$TESTRESULTS"
                    echo "Speed:" >> "./$TESTRESULTS"

                    if [ $rw = "reads" -o $rw = "readwrite" ]; then
                        echo running fio ./zfs/tests/zfs-tests/tests/perf/fio/mkfiles.fio $MODIFIER
                        fio ./zfs/tests/zfs-tests/tests/perf/fio/mkfiles.fio $MODIFIER >> /dev/null
                        sync
                    fi

                    echo running fio ./zfs/tests/zfs-tests/tests/perf/fio/$io'_'$rw.fio $MODIFIER --minimal --output="./TMP/$comp-$io-$rw.terse"
                    fio ./zfs/tests/zfs-tests/tests/perf/fio/$io'_'$rw.fio $MODIFIER --minimal --output="./TMP/$comp-$io-$rw.terse" >> /dev/null
                    sync

                    if [ "$OS" = "FreeBSD" ]; then
                        sed -i '' '1s/^/'"$comp;$io;$rw;$compressionratio;"'/' "./TMP/$comp-$io-$rw.terse"
                    else
                        sed -i '1s/^/'"$comp;$io;$rw;$compressionratio;"'/' "./TMP/$comp-$io-$rw.terse"
                    fi

                    bandwidth=$(awk -F ';' '{print $11}' ./TMP/$comp-$io-$rw.terse)
                    echo "$(($bandwidth/1000)) MB/s" >> "./$TESTRESULTS"
                    echo "" >> "./$TESTRESULTS"
                    rm -f /$TESTDATASET/*
                done
                echo ""  >> "./$TESTRESULTS"
                echo "----" >> "./$TESTRESULTS"
                echo "" >> "./$TESTRESULTS"
            fi
        done
        echo ""
        echo ""  >> "./$TESTRESULTS"
        echo ""  >> "./$TESTRESULTS"
        echo ""  >> "./$TESTRESULTS"
        sudo $ZFS_CMD destroy $TESTDATASET
    done

    cat ./Terse.Template ./TMP/*.terse > "./$TESTRESULTSTERSE"
    rm -rf ./TMP
    echo "compression test finished"
    if [ $TESTPOOL_MANAGE = "TRUE" ]; then
        echo "destroying pool"
        sudo $ZPOOL_CMD destroy $TESTPOOL_NAME 2>&1 >/dev/null
        echo "Cleaning ram"
        test -e /dev/shm/pooldisk.img && sudo rm -f /dev/shm/pooldisk.img
        [ -n "${MDDEV}" ] && sudo mdconfig -d -u ${MDDEV}
    fi
fi

if [ $RESET = "TRUE" ]; then
    cd ./zfs
    echo "unloading and unlinking zfs"
    sudo ./scripts/zfs.sh -u
    sudo ./scripts/zfs-helpers.sh -r
    make -s distclean >> /dev/null
    cd ..
fi
echo "Done."

if [  $MODE = "FULL" -o $MODE = "BASIC" -o $MODE = "CUSTOM" ]; then
    echo "compression results written to ./$TESTRESULTS"
    echo "Exported results to ./$TESTRESULTSTERSE"
fi
