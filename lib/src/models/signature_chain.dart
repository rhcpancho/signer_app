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

/// Origen de la comprobación de revocación.
enum RevocationSource { ocsp, crl }

/// Resultado de la comprobación de revocación (soft-fail).
///
/// `status.unknown` (null) = sin red, sin URLs AIA/CRL o parseo fallido;
/// nunca invalida la firma por sí solo.
class RevocationCheck {
  const RevocationCheck({
    required this.status,
    this.source,
    this.note,
    this.goodCount = 0,
    this.revokedCount = 0,
    this.skippedCount = 0,
  });

  /// `yes` = todos los nodos comprobados good; `no` = al menos uno revoked;
  /// `unknown` = no se pudo determinar (offline o sin datos).
  final CertValidity status;

  final RevocationSource? source;
  final String? note;

  final int goodCount;
  final int revokedCount;
  final int skippedCount;

  static const RevocationCheck unknown = RevocationCheck(
    status: CertValidity.unknown,
    note: 'Sin comprobar',
  );
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
    this.issuerNameDer,
    this.spkiDer,
    this.ocspUrls = const <String>[],
    this.crlUrls = const <String>[],
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

  /// DER del campo issuer (Name) del propio cert — para OCSP issuerNameHash.
  final List<int>? issuerNameDer;

  /// DER completo del SubjectPublicKeyInfo — para extraer la clave emisora.
  final List<int>? spkiDer;

  /// URLs AIA → OCSP (id-ad-ocsp).
  final List<String> ocspUrls;

  /// URLs CRL Distribution Points.
  final List<String> crlUrls;
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
    this.revocation,
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

  /// Resultado OCSP/CRL (soft-fail; null = aún no comprobado).
  final RevocationCheck? revocation;

  /// Mensaje de error no fatal (parseo parcial, algoritmo soportado…).
  final String? error;

  /// Atajo para la UI: `signatureValidates` o fallback a integridad.
  bool get analysed => signatureValidates != null || documentIntegrityOk != null;

  SignatureChainInfo withRevocation(RevocationCheck check) {
    return SignatureChainInfo(
      documentIntegrityOk: documentIntegrityOk,
      signatureCryptographicOk: signatureCryptographicOk,
      signatureValidates: signatureValidates,
      chainComplete: chainComplete,
      chainNodes: chainNodes,
      digestAlgorithmOid: digestAlgorithmOid,
      signatureAlgorithmOid: signatureAlgorithmOid,
      signingTime: signingTime,
      revocation: check,
      error: error,
    );
  }

  static const SignatureChainInfo empty = SignatureChainInfo(
    documentIntegrityOk: null,
    signatureCryptographicOk: null,
    signatureValidates: null,
    chainComplete: false,
    chainNodes: <CertChainNode>[],
    digestAlgorithmOid: null,
    signatureAlgorithmOid: null,
    signingTime: null,
    revocation: null,
  );
}
