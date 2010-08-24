#!/bin/bash
#
# Copyright (c) 2006-2010 Linagora
# http://github.com/Tauop/ScriptCollection
#
# ScriptCollection is free software, you can redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# ScriptCollection is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# README ---------------------------------------------------------------------
# this script aim to check a rails database. Sometimes, rails migration are not
# well coded, and add foreign keys errors. This script try to detect those
# errors.
#
# Usage: ./check_rails_db.sh
# Author: Patrick Guiran <pguiran@linagora.com>
#
# Note : Depends on ScriptHelper (http://github.com/Tauop/ScriptHelper), which
#        has to be present in ../lib directory


. ../lib/functions.lib.sh
SOURCE ../lib/mysql.lib.sh
SOURCE ../lib/ask.lib.sh

mysql_host=
mysql_user=
mysql_pass=
mysql_db=

MSG "Get MySQL information"
ASK mysql_host        "MySQL host ? "
ASK mysql_user        "User login ? "
ASK --pass mysql_pass "User password ? "
ASK mysql_db          "Database name ? "
BR

MYSQL_SET_CONF --host "${mysql_host}" --user "${mysql_user}" --pass "${mysql_pass}" --db "${mysql_db}"

table_list=$( MYSQL_GET_TABLES | tr $'\n' ' ')

for table in ${table_list}; do
  MSG "=== Analysing ${table} ==="
  MSG_INDENT_INC

  fields=$( MYSQL_GET_FIELDS ${table} )
  fields_with_id=$( echo "${fields}" | grep '_id$' | tr $'\n' ' ')
  has_id=$( echo "${fields}" | grep '^id$' )
  [ -z "${has_id}" ] && has_id='false' || has_id='true'

  for field in ${fields_with_id}; do
    foreign_table=${field%_id}

    # foreign_table is not in table_list -> no check
    [ "${table_list/ $foreign_table? /}" = "${table_list}" ] && continue

    field_type=$( MYSQL_GET_FIELD_TYPE "${table}" "${field}")
    [ "${field_type}" != "${field_type/varchar/}" ] && continue

    foreign_table=$( echo "${table_list}" | tr ' ' $'\n' | grep "^${foreign_table}.$" )

    MESSAGE --no-break ". check ${table}.${field} on ${foreign_table} "

    bad_values=$(
       MYSQL_QUERY "SELECT DISTINCT \`${table}\`.\`${field}\`
                    FROM \`${table}\`
                    LEFT JOIN \`${foreign_table}\` ON \`${table}\`.\`${field}\` = \`${foreign_table}\`.\`id\`
                    WHERE \`${foreign_table}\`.\`id\` IS NULL
                      AND \`${table}\`.\`${field}\` IS NOT NULL
                      AND \`${table}\`.\`${field}\` != 0 " \
      )
    nb_bad_values=$( echo -n "${bad_values}" | wc -l)
    bad_values=$( echo -n "${bad_values}" | tr $'\n' ',' | sed -e 's/,/, /g' )

    if [ -n "${bad_values}" ]; then
      nb_bad_values=$(( nb_bad_values + 1 ))
      MSG_INDENT_INC
      MSG --no-indent "-> ${nb_bad_values} BAD VALUES"
      MSG "${table}.${field} bad = ${bad_values}" | fold -s

      if [ "${has_id}" = 'true' ]; then
        bad_values_id=$(
           MYSQL_QUERY "SELECT DISTINCT \`${table}\`.\`id\`
                        FROM \`${table}\`
                        LEFT JOIN \`${foreign_table}\` ON \`${table}\`.\`${field}\` = \`${foreign_table}\`.\`id\`
                        WHERE \`${foreign_table}\`.\`id\` IS NULL
                          AND \`${table}\`.\`${field}\` IS NOT NULL
                          AND \`${table}\`.\`${field}\` != 0 " \
          )

        bad_values_id=$( echo -n "${bad_values_id}" | tr $'\n' ',' | sed -e 's/,/, /g' )
        MSG "${table}.id where values are bad = ${bad_values_id}" | fold -s
      fi

      MSG_INDENT_DEC
    else
      MSG --no-indent "-> All is OK"
    fi
  done
  MSG_INDENT_DEC
done

BR
MSG "FINISH"
BR

exit 0
