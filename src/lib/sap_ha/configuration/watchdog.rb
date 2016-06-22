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
# Summary: SUSE High Availability Setup for SAP Products: Watchdog configuration
# Authors: Ilya Manyugin <ilya.manyugin@suse.com>

require 'yast'
require 'sap_ha/system/watchdog'
require_relative 'base_config'

module SapHA
  module Configuration
    # Watchdog configuration
    class Watchdog < BaseConfig

      attr_reader :to_install, :configured, :proposals, :loaded

      include Yast::UIShortcuts

      def initialize
        super
        @screen_name = "Watchdog Setup"
        @loaded = System::Watchdog.loaded_watchdogs
        @configured = System::Watchdog.installed_watchdogs
        @to_install = []
        @proposals = System::Watchdog.list_watchdogs
      end

      def configured?
        !@loaded.empty? || !@configured.empty? || !@to_install.empty?
      end

      def description
        s = []
        s << "&nbsp; Configured modules: #{@configured.join(', ')}." unless @configured.empty?
        s << "&nbsp; Already loaded modules: #{@loaded.join(', ')}." unless @loaded.empty?
        s << "&nbsp; Modules to install: #{@to_install.join(', ')}." unless @to_install.empty?
        s.join('<br>')
      end

      def add_to_config(wdt_module)
        raise WatchdogConfigurationException,
          "Module #{wdt_module} is already configured." if @configured.include? wdt_module
        @to_install << wdt_module unless @to_install.include? wdt_module
      end

      def remove_from_config(wdt_module)
        return unless @to_install.include? wdt_module
        @to_install -= [wdt_module]
      end

      def apply(role)
        return false if !configured?
        @nlog.info('Appying Watchdog Configuration')
        stat = true
        @to_install.each do |module_name|
          stat &= System::Watchdog.install(module_name)
          stat &= System::Watchdog.load(module_name)
        end
        @nlog.log_status(stat,
          "Configured requested watchdog devices",
          "Could not configure requested watchdog devices")
        stat
      end
    end
  end
end