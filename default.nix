{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.proxycontainers;
  startIp = 11;
  makeIp = num: "192.168.100.${toString num}";
  makeSlug = num: toString num;
  sslServerCert = ../nix-gce/cert.pem;
  sslServerChain = ../nix-gce/fullchain.pem;
  sslServerKey = ../nix-gce/privkey.pem;
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
in {
  options = {
    proxycontainers = {
      enable = mkOption {
        type = types.bool;
        default = false;
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
    containers = mapAttrs' (name: value: nameValuePair "c${value.slug}" {
      config = value.config; # TODO inherit config (value);
      autoStart = true;
      privateNetwork = true;
      hostAddress = "192.168.100.10";
      localAddress = "${value.ip}";
    }) withIps;
    services.httpd = {
      enable = true;
      adminAddr = "kyle.sferrazza@gmail.com";
      virtualHosts = (mapAttrs (name: value: {
        hostName = name;
        extraConfig = ''
          ProxyPass "/" "http://${value.ip}:${value.port}/"
          ProxyPassReverse "/" "http://${value.ip}:${value.port}/"
        '';
        onlySSL = true;
        inherit sslServerCert sslServerChain sslServerKey;
      }) withIps) // {
        home = {
          hostName = "nix.kylesferrazza.com";
          documentRoot = ./default;
          onlySSL = true;
          inherit sslServerCert sslServerChain sslServerKey;
        };
        default = {
          documentRoot = let
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
          onlySSL = true;
          inherit sslServerCert sslServerChain sslServerKey;
        };
      };
    };
  });
}
