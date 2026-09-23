/// Semántica de validez tri-stada de una firma digital.
///
/// `true` / `false` = comprobado; `null` = no se pudo evaluar
/// (estructura ausente, algoritmo no soportado, error interno).
class CertValidity {
  const CertValidity._(this.value);

  final bool? value;

  static const CertValidity yes = CertValidity._(true);
  static const CertValidity no = CertValidity._(false);
  static const CertValidity unknown = CertValidity._(null);

  bool? get $value => value;
}

/// Un nodo de la cadena de certificados (leaf → root).
class CertChainNode {
  const CertChainNode({
    required this.subject,
    required this.issuer,
    required this.serialHex,
    required this.validFrom,
    required this.validTo,
    required this.isSelfSigned,
    required this.isCa,
    required this.basicConstraintsPresent,
    required this.validityAtSigning,
    required this.rawDer,
    this.subjectKeyIdentifier,
    this.authorityKeyIdentifier,
  });

  /// Subject DN legible (CN prioritario).
  final String subject;

  /// Issuer DN legible.
  final String issuer;

  /// Serial en hex (sin 0x, mayúsculas).
  final String serialHex;

  final DateTime? validFrom;
  final DateTime? validTo;

  /// `subject == issuer` (candidato a raíz).
  final bool isSelfSigned;

  /// basicConstraints.CA == true (o extensión ausente en nodo no-leaf).
  final bool isCa;

  final bool basicConstraintsPresent;

  /// Validez temporal respecto a la fecha de firma (o `now` si no se conoce).
  final CertValidity validityAtSigning;

  /// DER completo del certificado.
  final List<int> rawDer;

  final List<int>? subjectKeyIdentifier;
  final List<int>? authorityKeyIdentifier;
}

/// Resultado del análisis de una firma CMS/PKCS#7 embebida en un PDF.
class SignatureChainInfo {
  const SignatureChainInfo({
    required this.documentIntegrityOk,
    required this.signatureCryptographicOk,
    required this.signatureValidates,
    required this.chainComplete,
    required this.chainNodes,
    required this.digestAlgorithmOid,
    required this.signatureAlgorithmOid,
    required this.signingTime,
    this.error,
  });

  /// ByteRange cubre el documento y el messageDigest coincide.
  final bool? documentIntegrityOk;

  /// La firma RSA/ECDSA sobre los signedAttrs (o el contenido) es válida.
  final bool? signatureCryptographicOk;

  /// `documentIntegrityOk == true && signatureCryptographicOk == true`.
  final bool? signatureValidates;

  /// La cadena llega hasta una raíz self-signed con CA=true.
  final bool chainComplete;

  /// Leaf primero, raíz al final (o cadena incompleta).
  final List<CertChainNode> chainNodes;

  final String? digestAlgorithmOid;
  final String? signatureAlgorithmOid;
  final DateTime? signingTime;

  /// Mensaje de error no fatal (parseo parcial, algoritmo soportado…).
  final String? error;

  /// Atajo para la UI: `signatureValidates` o fallback a integridad.
  bool get analysed => signatureValidates != null || documentIntegrityOk != null;

  static const SignatureChainInfo empty = SignatureChainInfo(
    documentIntegrityOk: null,
    signatureCryptographicOk: null,
    signatureValidates: null,
    chainComplete: false,
    chainNodes: <CertChainNode>[],
    digestAlgorithmOid: null,
    signatureAlgorithmOid: null,
    signingTime: null,
  );
}
