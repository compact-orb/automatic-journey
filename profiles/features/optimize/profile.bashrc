_opt_strip_flag() {
    local var="$1" pattern="$2" new_val="" word
    for word in ${!var}; do
        case "$word" in
            $pattern) ;;
            *) new_val="${new_val:+$new_val }$word" ;;
        esac
    done
    printf -v "$var" "%s" "$new_val"
}

_opt_translate_flag() {
    local var="$1" from="$2" to="$3" new_val="" word
    for word in ${!var}; do
        case "$word" in
            $from) new_val="${new_val:+$new_val }$to" ;;
            *) new_val="${new_val:+$new_val }$word" ;;
        esac
    done
    printf -v "$var" "%s" "$new_val"
}

_opt_is_gcc() {
    if declare -f tc-is-gcc >/dev/null && tc-is-gcc; then
        return 0
    fi
    local cc="${CC:-$(tc-getCC 2>/dev/null)}"
    local cxx="${CXX:-$(tc-getCXX 2>/dev/null)}"
    local cc_bin="${cc##*/}"; cc_bin="${cc_bin%% *}"
    local cxx_bin="${cxx##*/}"; cxx_bin="${cxx_bin%% *}"

    if [[ "${cc_bin}" =~ (^|-)gcc$ || "${cxx_bin}" =~ (^|-)g\+\+$ || "${CATEGORY}/${PN}" == "sys-devel/gcc" || "${CATEGORY}/${PN}" == "sys-libs/glibc" ]]; then
        return 0
    fi
    return 1
}

sanitize_gcc_flags() {
    if _opt_is_gcc; then
        local v
        for v in CFLAGS CXXFLAGS FFLAGS FCFLAGS; do
            _opt_strip_flag "$v" "-Xclang=-mllvm"
            _opt_strip_flag "$v" "-Xclang=-polly*"
            _opt_strip_flag "$v" "-mllvm"
            _opt_strip_flag "$v" "-polly*"
            _opt_translate_flag "$v" "-flto=thin" "-flto=auto"
        done

        _opt_strip_flag LDFLAGS "-Wl,--lto-O3"
        _opt_strip_flag LDFLAGS "-Wl,--undefined-version"
        _opt_translate_flag LDFLAGS "-fuse-ld=lld" "-fuse-ld=bfd"
        _opt_translate_flag LDFLAGS "-flto=thin" "-flto=auto"
    fi
}

sanitize_polly_flags() {
    _opt_is_gcc && return 0

    local cc="${CC:-clang}"
    if declare -f tc-getCC >/dev/null; then
        cc="$(tc-getCC 2>/dev/null)"
        cc="${cc:-${CC:-clang}}"
    fi

    if [[ "${_OPT_POLLY_TESTED_CC}" != "${cc}" ]]; then
        _OPT_POLLY_TESTED_CC="${cc}"
        if ${cc} -Xclang=-mllvm -Xclang=-polly -x c -c /dev/null -o /dev/null 2>/dev/null; then
            _OPT_POLLY_SUPPORTED=1
        else
            _OPT_POLLY_SUPPORTED=0
        fi
    fi

    if [[ "${_OPT_POLLY_SUPPORTED}" -eq 0 ]]; then
        if [[ -z "${_OPT_POLLY_WARNED+x}" ]]; then
            _OPT_POLLY_WARNED=1
            if declare -f ewarn >/dev/null; then
                ewarn "LLVM Polly is not supported by ${cc}; stripping Polly optimization flags."
            fi
        fi

        local v
        for v in CFLAGS CXXFLAGS FFLAGS FCFLAGS CGO_CFLAGS CGO_CXXFLAGS; do
            _opt_strip_flag "$v" "-Xclang=-mllvm"
            _opt_strip_flag "$v" "-Xclang=-polly*"
            _opt_strip_flag "$v" "-mllvm"
            _opt_strip_flag "$v" "-polly*"
        done
        _opt_strip_flag KCFLAGS "-mllvm"
        _opt_strip_flag KCFLAGS "-polly*"
    fi
}

sanitize_lld_flags() {
    _opt_is_gcc && return 0

    local cc="${CC:-clang}"
    if declare -f tc-getCC >/dev/null; then
        cc="$(tc-getCC 2>/dev/null)"
        cc="${cc:-${CC:-clang}}"
    fi

    if [[ "${_OPT_LLD_TESTED_CC}" != "${cc}" ]]; then
        _OPT_LLD_TESTED_CC="${cc}"
        local out
        out="$(${cc} -fuse-ld=lld -Wl,--version -x c /dev/null 2>/dev/null)"
        if [[ "${out}" =~ (LLD|lld) ]]; then
            _OPT_LLD_SUPPORTED=1
        else
            _OPT_LLD_SUPPORTED=0
        fi
    fi

    if [[ "${_OPT_LLD_SUPPORTED}" -eq 0 ]]; then
        if [[ -z "${_OPT_LLD_WARNED+x}" ]]; then
            _OPT_LLD_WARNED=1
            if declare -f ewarn >/dev/null; then
                ewarn "LLD linker is not supported by ${cc}; stripping LLD optimization flags."
            fi
        fi

        local v
        for v in CFLAGS CXXFLAGS FFLAGS FCFLAGS CGO_CFLAGS CGO_CXXFLAGS; do
            _opt_strip_flag "$v" "-flto=thin"
        done
        for v in LDFLAGS CGO_LDFLAGS; do
            _opt_strip_flag "$v" "-fuse-ld=lld"
            _opt_strip_flag "$v" "-Wl,--lto-O3"
            _opt_strip_flag "$v" "-Wl,--undefined-version"
            _opt_strip_flag "$v" "-flto=thin"
        done
    fi
}

sanitize_flags() {
    sanitize_gcc_flags
    sanitize_polly_flags
    sanitize_lld_flags
}

sanitize_flags
pre_src_prepare() { sanitize_flags; }
pre_src_configure() { sanitize_flags; }
pre_src_compile() { sanitize_flags; }
