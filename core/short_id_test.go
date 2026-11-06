package core

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/config"
)

func TestHandleGetConfigKeepsAnUnquotedShortIDAsWritten(t *testing.T) {
	profile := `proxies:
  - name: octal
    type: vless
    reality-opts: {public-key: k, short-id: 0123}
  - name: zeros
    type: vless
    reality-opts:
      short-id: 00
  - name: exponent
    type: vless
    reality-opts:
      short-id: 1e5
  - name: quoted
    type: vless
    reality-opts:
      short-id: "0189"
  - name: hex
    type: vless
    reality-opts:
      short-id: 0a1b
listeners:
  - name: in
    type: vless
    reality-config:
      short-id: [01234567, ""]
`
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte(profile), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	raw, err := readRawConfig(path)
	if err != nil {
		t.Fatalf("handleGetConfig = %v", err)
	}

	want := map[string]string{
		"octal":    "0123",
		"zeros":    "00",
		"exponent": "1e5",
		"quoted":   "0189",
		"hex":      "0a1b",
	}
	for _, proxy := range raw.Proxy {
		name := proxy["name"].(string)
		got := proxy["reality-opts"].(map[string]any)["short-id"]
		if got != want[name] {
			t.Errorf("%s short-id = %#v, want %q", name, got, want[name])
		}
	}
	ids := raw.Listeners[0]["reality-config"].(map[string]any)["short-id"].([]any)
	if ids[0] != "01234567" || ids[1] != "" {
		t.Errorf("listener short-id = %#v, want [01234567 \"\"]", ids)
	}
}

func TestHandleGetConfigLeavesProfilesWithoutShortIDsToMihomo(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("mixed-port: 7899\n"), 0o600); err != nil {
		t.Fatalf("write profile: %v", err)
	}

	raw, err := readRawConfig(path)
	if err != nil {
		t.Fatalf("handleGetConfig = %v", err)
	}
	if raw.MixedPort != 7899 || raw.Mode.String() == "" {
		t.Errorf("raw config = port %d mode %q, want 7899 and the default mode", raw.MixedPort, raw.Mode)
	}
}

func TestUnmarshalRawConfigMatchesMihomoWithoutNumericShortIDs(t *testing.T) {
	for name, profile := range map[string]string{
		"quoted":    `proxies: [{name: p, type: vless, reality-opts: {short-id: "0123"}}]`,
		"hex":       `proxies: [{name: p, type: vless, reality-opts: {short-id: 0a1b}}]`,
		"comment":   "# short-id is not configured\nmixed-port: 7899\n",
		"empty":     "# short-id\n",
		"null":      "null # short-id\n",
		"scalar":    "not a config # short-id\n",
		"malformed": "proxies: [ # short-id\n",
		"duplicate": "mixed-port: 1\nmixed-port: 2 # short-id\n",
	} {
		t.Run(name, func(t *testing.T) {
			want, wantErr := config.UnmarshalRawConfig([]byte(profile))
			got, gotErr := unmarshalRawConfig([]byte(profile))
			if !reflect.DeepEqual(got, want) || fmt.Sprint(gotErr) != fmt.Sprint(wantErr) {
				t.Errorf("unmarshalRawConfig = (%#v, %v), want (%#v, %v)", got, gotErr, want, wantErr)
			}
		})
	}
}

func TestUnmarshalRawConfigPreservesEncryptedProfiles(t *testing.T) {
	secret, public, err := age.GenX25519KeyPair()
	if err != nil {
		t.Fatal(err)
	}
	age.SetGlobalSecretKeys(secret)
	t.Cleanup(func() { age.SetGlobalSecretKeys() })
	encrypted, err := age.EncryptBytes([]byte("mixed-port: 7899\n"), public)
	if err != nil {
		t.Fatal(err)
	}
	for name, profile := range map[string][]byte{
		"encrypted":                       encrypted,
		"encrypted with short-id comment": append(bytes.Clone(encrypted), []byte("# short-id\n")...),
		"invalid armor":                   []byte(age.FileHeader + "\nshort-id\n"),
	} {
		t.Run(name, func(t *testing.T) {
			want, wantErr := config.UnmarshalRawConfig(profile)
			got, gotErr := unmarshalRawConfig(profile)
			if !reflect.DeepEqual(got, want) || fmt.Sprint(gotErr) != fmt.Sprint(wantErr) {
				t.Errorf("unmarshalRawConfig = (%#v, %v), want (%#v, %v)", got, gotErr, want, wantErr)
			}
		})
	}
}
