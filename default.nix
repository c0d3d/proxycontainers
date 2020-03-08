{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.proxycontainers;
  startIp = 11;
  makeIp = num: "192.168.100.${toString num}";
  makeSlug = num: toString num;
  addIps = (set:
    let
      names = builtins.attrNames set;
      folded = lib.lists.foldr (cur: acc:
        let
          val = builtins.getAttr cur set;
          newVal = val // { ip = makeIp acc.idx; slug = makeSlug acc.idx; };
          newItems = acc.items // { "${cur}" = newVal; };
          newIdx = acc.idx + 1;
        in { items = newItems; idx = newIdx; }
        ) { idx = startIp; items = {}; } names;
    in folded.items
  );
  makeContainerDef = (name: value: nameValuePair "c${value.slug}" {
      config = value.config; # TODO inherit config (value);
      autoStart = true;
      privateNetwork = true;
      hostAddress = "192.168.100.10";
      localAddress = "${value.ip}";
  });
in {
  options = {
    proxycontainers = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      acceptTOS = mkOption {
        type = types.bool;
        default = false; # Just to force people to enable
      };
      adminAddr = mkOption {
        type = types.str;
      };
      rootDomain = mkOption {
        type = types.str;
      };
      enableACMERoot = mkOption {
        type = types.bool;
        default = false;
      };
      forceSSLRoot = mkOption {
        type = types.bool;
        default = true;
      };
      recommendedOptimisation = mkOption {
        type = types.bool;
        default = true;
      };
      recommendedTlsSettings = mkOption {
        type = types.bool;
        default = true;
      };
      recommendedGzipSettings = mkOption {
        type = types.bool;
        default = true;
      };
      hsts = mkOption {
        type = types.str;
        default = "add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;";
      };
      sslCertificateRoot = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      sslTrustedCertificate = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      sslCertificateKey = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      containers = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            ip = mkOption {
              type = types.str;
            };
            port = mkOption {
              type = types.str;
              default = "80";
            };
            enableACME = mkOption {
              type = types.bool;
              default = false;
            };
            forceSSL = mkOption {
              type = types.bool;
              default = true;
            };
            sslCertificate = mkOption {
              type = types.nullOr types.path;
              default = null;
            };
            sslServerChain = mkOption {
              type = types.nullOr types.path;
              default = null;
            };
            sslServerKey = mkOption {
              type = types.nullOr types.path;
              default = null;
            };
            config = mkOption {
              default = {};
            };
          };
        });
        default = {};
      };
    };
  };
  config = mkIf (cfg.enable)
  (let
    withIps = addIps cfg.containers;
  in {
    security.acme.acceptTerms = cfg.acceptTOS;
    security.acme.email = cfg.adminAddr;
    containers = mapAttrs' makeContainerDef withIps;
    services.nginx = {
      enable = true;
      recommendedTlsSettings = cfg.recommendedTlsSettings;
      recommendedOptimisation = cfg.recommendedOptimisation;
      recommendedGzipSettings = cfg.recommendedGzipSettings;
      virtualHosts = (mapAttrs (name: value: {
        serverName = name;
        enableACME = value.enableACME;
        forceSSL = value.forceSSL;
        sslCertificate = if value.sslCertificate != null
                         then value.sslCertificate
                         else "/var/lib/acme/default/fullchain.pem";
        sslCertificateKey = if value.sslServerKey != null
                            then value.sslServerKey
                            else "/var/lib/acme/default/key.pem";
        sslTrustedCertificate = if value.sslServerChain != null
                                then value.sslServerChain
                                else "/var/lib/acme/default/full.pem";
        extraConfig = ''
          ${cfg.hsts}
          proxy_set_header X-Forwarded-Host $host:$server_port;
          proxy_set_header X-Forwarded-Server $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          location "/" {
            proxy_pass "http://${value.ip}:${value.port}/";
          }
        '';
      }) withIps) // {
        default = {
          serverName = cfg.rootDomain;
          root = let
            names = attrNames withIps;
            listItems = map (name: "<li><a href=\"//${name}\">${name}</a></li>\n") names;
            str = builtins.concatStringsSep "" listItems;
          in "${(pkgs.writeTextDir "home/index.html" ''
            <h1>This route is not configured.</h1>
            <h2>Configured routes:</h2>
            <ul>
              ${str}
            </ul>
          '')}/home/";

          enableACME = cfg.enableACMERoot;
          forceSSL = cfg.forceSSLRoot;

          sslCertificate = if value.sslCertificateRoot != null
                           then value.sslCertificateRoot
                           else "/var/lib/acme/default/fullchain.pem";
          sslCertificateKey = if value.sslCertificateKey != null
                              then value.sslCertificateKey
                              else "/var/lib/acme/default/key.pem";
          sslTrustedCertificate = if value.sslTrustedCertificate != null
                                  then value.sslTrustedCertificate
                                  else "/var/lib/acme/default/full.pem";
        };
      };
    };
  });
}
