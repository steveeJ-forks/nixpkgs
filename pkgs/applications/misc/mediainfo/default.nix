{ stdenv, fetchurl, automake, autoconf, libtool, pkgconfig, libzen, libmediainfo, zlib }:

stdenv.mkDerivation rec {
  version = "0.7.80";
  name = "mediainfo-${version}";
  src = fetchurl {
    url = "http://mediaarea.net/download/source/mediainfo/${version}/mediainfo_${version}.tar.xz";
    sha256 = "12iwiw4vcmyi8l04j540kbqifmr1wnlfw5cway185iqia43s6c10";
  };

  buildInputs = [ automake autoconf libtool pkgconfig libzen libmediainfo zlib ];

  sourceRoot = "./MediaInfo/Project/GNU/CLI/";

  configureFlags = [ "--with-libmediainfo=${libmediainfo}" ];
  preConfigure = "sh autogen.sh";

  meta = with stdenv.lib; {
    description = "Supplies technical and tag information about a video or audio file";
    longDescription = ''
      MediaInfo is a convenient unified display of the most relevant technical
      and tag data for video and audio files.
    '';
    homepage = http://mediaarea.net/;
    license = licenses.bsd2;
    platforms = platforms.unix;
    maintainers = [ maintainers.devhell ];
  };
}
