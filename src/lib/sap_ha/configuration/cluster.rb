# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE Linux GmbH, Nuernberg, Germany.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
#
# Summary: SUSE High Availability Setup for SAP Products: Cluster members configuration
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'erb'
require 'socket'
require_relative 'base_config'
require 'sap_ha/system/local'
require 'sap_ha/exceptions'

Yast.import 'UI'

module SapHA
  module Configuration
    # Cluster members configuration
    # TODO: think of merging this one and the CommLayer
    class Cluster < BaseConfig
      attr_reader :nodes, :number_of_rings, :transport_mode, :fixed_number_of_nodes
      attr_accessor :cluster_name, :expected_votes

      include Yast::UIShortcuts
      include SapHA::Exceptions

      def initialize
        super()
        @screen_name = "Cluster Configuration"
        @fixed_number_of_nodes = false
        @number_of_nodes = 2
        @number_of_rings = 1
        @nodes = {}
        @rings = {}
        @transport_mode = :unicast
        @number_of_rings = 1
        @expected_votes = 2
        @exception_type = ClusterConfigurationException
        @cluster_name = 'hacluster'
        init_rings
        init_nodes
      end

      def set_fixed_nodes(fixed, number)
        @fixed_number_of_nodes = fixed
        @number_of_nodes = number
        init_nodes
      end

      def node_parameters(node_id)
        @nodes[node_id]
      end

      # return the table-like representation
      def nodes_table_cont
        @nodes.map do |node_id, value|
          it = Item(Id(node_id), value[:node_id], value[:host_name], value[:ip_ring1])
          it << value[:ip_ring2] if @number_of_rings >= 2
          it << value[:ip_ring3] if @number_of_rings == 3
          it
        end
      end

      def number_of_rings=(value)
        @number_of_rings = value
        # reinit the items
        rings_old = @rings.dup
        @rings = {}
        (1..@number_of_rings).each do |ix|
          key = "ring#{ix}".to_sym
          if rings_old.key?(key)
            @rings[key] = rings_old[key]
          else
            @rings[key] = {
              address: '',
              port:    '',
              id:      ix,
              mcast:   ''
            }
          end
        end
      end

      def ring_info(ring_id)
        @rings[ring_id]
      end

      def multicast?
        @transport_mode == :multicast
      end

      def all_rings
        @rings.dup
      end

      def rings_table_cont
        if multicast?
          @rings.map { |k, v| Item(Id(k), k.to_s, v[:address], v[:port], v[:mcast]) }
        else
          @rings.map { |k, v| Item(Id(k), k.to_s, v[:address], v[:port]) }
        end
      end

      def update_ring(ring_id, values)
        [:address, :port].each { |e| @rings[ring_id][e] = values[e] }
        @rings[ring_id][:mcast] = values[:mcast] if multicast?
      end

      def transport_mode=(value)
        unless [:multicast, :unicast].include? value
          raise ModelValidationException,
            "Error setting transport mode to #{value}"
        end
        @transport_mode = value
      end

      def configured?
        # TODO: check if our IP in the IP list
        flag = @rings.all? { |_, v| validate_ring(v, :silent) }
        flag &= SemanticChecks.instance.check(:silent) do |check|
          check.equal(@rings.length, @number_of_rings, 'Number of table entries is not
            equal to the number of allowed rings.')
          check.identifier(@cluster_name, 'Cluster name is incorrect')
          check.integer_in_range(@expected_votes, 1, @nodes.length)
        end
        return flag unless flag
        flag &= @nodes.all? { |_, v| validate_node(v, :silent) }
        return flag unless flag
        flag &= SemanticChecks.instance.check(:silent) do |check|
          check.unique(@nodes.map { |_, v| v[:ip_ring1] }, 'IP addresses in the ring #1 are not unique')
          check.ips_belong_to_net(@nodes.map { |_, v| v[:ip_ring1] },
            @rings[:ring1][:address])
          if @number_of_rings >= 2
            check.unique(@nodes.map { |_, v| v[:ip_ring2] }, 'IP addresses in the ring #2 are not unique') if @number_of_rings >= 2
            check.ips_belong_to_net(@nodes.map { |_, v| v[:ip_ring2] },
              @rings[:ring2][:address]
            )
          end
          if @number_of_rings == 3
            check.unique(@nodes.map { |_, v| v[:ip_ring3] }, 'IP addresses in the ring #3 are not unique')
            check.ips_belong_to_net(@nodes.map { |_, v| v[:ip_ring3] },
              @rings[:ring3][:address])
          end
        end
        flag
      end

      def update_values(k, values)
        @nodes[k] = values
      end

      def validate_ring(ring, verbosity)
        SemanticChecks.instance.check(verbosity) do |check|
          check.ipv4(ring[:address], 'IP Address')
          check.port(ring[:port], 'Port Number')
          check.ipv4_multicast(ring[:mcast], 'Multicast Address') if multicast?
        end
      end

      def render_csync2_config(group_name, includes, key_path, hosts)
        return SapHA::Helpers.render_template('tmpl_csync2_config.erb', binding)
      end

      def description
        tmp = ERB.new(
          '&nbsp; Transport mode: <%= @transport_mode %>.<br>
          &nbsp; Cluster name: <%= @cluster_name %>.<br>
          &nbsp; Expected votes: <%= @expected_votes %>.<br>
          &nbsp; Rings:<br>
          <% @rings.each_with_index do |(k, ring), ix| -%>
              &nbsp; <%= ring[:id] %>. <%= ring[:address] %>, port <%= ring[:port] %>
              <% if multicast? -%>
                <%= ring[:mcast] -%>
              <% end -%>
              <br>
          <% end -%>
          &nbsp; Nodes:<br>
          <% @nodes.each_with_index do |(k, nd), ix| %>
            <% ips = [nd[:ip_ring1], nd[:ip_ring2], nd[:ip_ring3]][0...@number_of_rings].join(", ") %>
            <%= "&nbsp; #{nd[:node_id]}. #{nd[:host_name]} (#{ips})." %>
            <% if ix != (@nodes.length-1) %>
              <%= "<br>" %>
            <% end %>
          <% end %>
          ', 1, '-')
        tmp.result(binding)
      end

      def add_node(values)
        if @fixed_number_of_nodes
          log.error "Scenario defined a fixed number of nodes #{@number_of_nodes},"\
            " but #{self.class}.#{__callee__} was called."
          return
        end
        # TODO: NW
      end

      def remove_node(node_id)
        if @fixed_number_of_nodes
          log.error "Scenario defined a fixed number of nodes #{@number_of_nodes},"\
            " but #{self.class}.#{__callee__} was called."
          return
        end
        # TODO: NW
      end

      # return IPs of the first ring for nodes other than current node
      def other_nodes
        ips = @nodes.map { |_, n| n[:ip_ring1] } - SapHA::System::Local.ip_addresses
        raise ClusterMembersConfException, "Empty IPs detected" if ips.any? { |e| e.empty? }
        ips
      end

      # TODO: rename and document
      def other_nodes_ext
        others_ip = other_nodes
        @nodes.map do |k, node|
          next unless others_ip.include? node[:ip_ring1]
          {hostname: node[:host_name], ip: node[:ip_ring1]}
        end.compact
      end

      def validate
        # TODO
        super
      end

      def validate_node(node, verbosity)
        SemanticChecks.instance.check(verbosity) do |check|
          check.ipv4(node[:ip_ring1], 'IP Ring 1')
          check.ipv4(node[:ip_ring2], 'IP Ring 2') if @number_of_rings > 1
          check.ipv4(node[:ip_ring3], 'IP Ring 3') if @number_of_rings > 2
          check.hostname(node[:host_name], 'Hostname')
          check.nonneg_integer(node[:node_id], 'Node ID')
        end
      end

      def apply(role)
        @nlog.info('Applying Cluster Configuration')
        flag = true
        flag &= cluster_apply
        status = SapHA::System::Local.start_cluster_services
        flag &= status
        @nlog.log_status(status, 'Enabled and started cluster-required systemd units',
          'Could not enable and start cluster-required systemd units')
        flag &= SapHA::System::Local.add_stonith_resource if role == :master
        status = SapHA::System::Local.open_ports(role, @rings, @number_of_rings)
        flag &= status
        @nlog.log_status(status, 'Opened necessary communication ports',
          'Could not open necessary communication ports')
        flag
      end

      private

      def init_nodes
        (1..@number_of_nodes).each do |i|
          @nodes["node#{i}".to_sym] = {
            host_name: "node#{i}",
            ip_ring1:  '',
            ip_ring2:  '',
            ip_ring3:  '',
            node_id:   i.to_s
          }
        end
      end

      def init_rings
        (1..@number_of_rings).each do |ix|
          @rings["ring#{ix}".to_sym] = {
            address: '',
            port:    '5405',
            id:      ix,
            mcast:   ''
          }
        end
      end

      def generate_corosync_key

      end

      def generate_csync2_key
      end

      def change_password_for_hawk
        # is to be called on all the nodes
        `echo "sapcluster" | passwd hacluster --stdin`
      end

      def cluster_apply
        log.error "@nodes=#{@nodes}"
        log.error "@rings=#{@rings}"
        return unless configured?
        memberaddr = @nodes.map { |_, e| {addr1: e[:ip_ring1]} }
        host_names = @nodes.map { |_, e| e[:host_name] }
        included_files = [
          '/etc/corosync/corosync.conf',
          '/etc/corosync/authkey',
          '/etc/sysconfig/pacemaker',
          '/etc/drbd.d',
          '/etc/drbd.conf',
          '/etc/lvm/lvm.conf',
          '/etc/multipath.conf',
          '/etc/ha.d/ldirectord.cf',
          '/etc/ctdb/nodes',
          '/etc/samba/smb.conf',
          '/etc/booth',
          '/etc/sysconfig/sbd',
          '/etc/csync2/csync2.cfg',
          '/etc/csync2/key_hagroup'
        ]
        cluster_export = {    "secauth" => true,
          "transport" => "udpu",
          "bindnetaddr1" => @rings[:ring1][:address],
          "memberaddr" => memberaddr,
          "mcastaddr1" => "",
          "cluster_name" => @cluster_name,
          "expected_votes" => @expected_votes.to_s,
          "two_node" => "1",
          # TODO: it seems this is not reflected in the config
          "mcastport1" => @rings[:ring1][:port],
          "enable2" => false, # use the second ring?
          "bindnetaddr2" => "",
          "mcastaddr2" => "",
          "mcastport2" => "",
          "autoid" => true,
          "rrpmode" => "none",
          "csync2_host" => host_names,
          "csync2_include" => included_files
        }
        SapHA::System::Local.yast_cluster_export(cluster_export)
      end
    end
  end
end