// statsheet prints the character sheet wowsims computes for one setup: the final stats and pseudo-stats of the
// player, as JSON {"stats": {"StatAttackPower": 1234, ...}, "pseudo": {"PseudoStatMeleeCritPercent": 21.5, ...}}.
//
// Input on stdin: the IndividualSimSettings protojson that `wowsimcli siml parse -json file.siml` prints.
// data/wowsims_update.ps1 builds it next to wowsimcli, against the same wowsims commit.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/wowsims/forever/sim"
	"github.com/wowsims/forever/sim/core"
	"github.com/wowsims/forever/sim/core/proto"
	"google.golang.org/protobuf/encoding/protojson"
)

func orEmpty[T any, P interface{ *T }](p P) P {
	if p == nil {
		return new(T)
	}
	return p
}

func main() {
	sim.RegisterAll()
	in, err := io.ReadAll(os.Stdin)
	if err != nil {
		fail(err)
	}
	s := &proto.IndividualSimSettings{}
	if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(in, s); err != nil {
		fail(err)
	}
	raid := core.SinglePlayerRaidProto(s.Player, orEmpty(s.PartyBuffs), orEmpty(s.RaidBuffs), orEmpty(s.Debuffs))
	enc := s.Encounter
	if enc == nil || len(enc.Targets) == 0 {
		enc = &proto.Encounter{Duration: 180, Targets: []*proto.Target{core.FreshDefaultTargetConfig()}}
	}
	res := core.ComputeStats(&proto.ComputeStatsRequest{Raid: raid, Encounter: enc})
	final := res.RaidStats.Parties[0].Players[0].FinalStats
	out := map[string]map[string]float64{"stats": {}, "pseudo": {}}
	for i, v := range final.Stats {
		out["stats"][proto.Stat(i).String()] = v
	}
	for i, v := range final.PseudoStats {
		out["pseudo"][proto.PseudoStat(i).String()] = v
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "statsheet:", err)
	os.Exit(1)
}
